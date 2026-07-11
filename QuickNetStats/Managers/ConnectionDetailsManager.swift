//
//  ConnectionDetailsManager.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-04.
//

import Foundation
import Combine

/// Assembles advanced connection details from the three readers and drives the
/// optional live-metrics polling loop. Main-actor isolated (project default);
/// never throws to the UI — any value a reader can't determine is simply absent.
class ConnectionDetailsManager: ObservableObject {

    // MARK: - Published State

    /// The last assembled static snapshot; nil until the first `fetchDetails()`.
    @Published private(set) var details: ConnectionDetails?

    /// The latest live sample; nil unless live polling is active.
    @Published private(set) var liveStats: LiveConnectionStats?

    /// Whether the live polling loop is running.
    @Published private(set) var isLive = false

    // MARK: - Dependencies

    private let systemConfig: SystemConfigReading
    private let interfaceReader: InterfaceReading
    private let wifiReader: WifiReading
    private let pathReader: PathReading
    private let session: URLSession
    private let pollInterval: TimeInterval

    /// The running poll loop, if any.
    private var liveTask: Task<Void, Never>?

    /// The in-flight refetch scheduled by a connection change, cancelled and
    /// replaced if another change arrives before it finishes so a superseded
    /// (cancelled) fetch never publishes stale data.
    private var changeTask: Task<Void, Never>?

    /// Retains the connection-change subscription so `observeConnectionChanges`
    /// only ever subscribes once.
    private var connectionChangeCancellable: AnyCancellable?

    /// A full counter sample taken at a point in time, used to compute per-second
    /// deltas for throughput, packet, error, and drop rates.
    private struct CounterSample {
        let rxBytes: UInt64
        let txBytes: UInt64
        let rxPackets: UInt64
        let txPackets: UInt64
        let errors: UInt64      // combined in + out
        let drops: UInt64
        let at: Date
    }

    /// The previous counter sample, used to compute per-second deltas.
    private var previousSample: CounterSample?

    // MARK: - Initializer

    init(
        systemConfig: SystemConfigReading = SystemConfigReader(),
        interfaceReader: InterfaceReading = InterfaceReader(),
        wifiReader: WifiReading = WifiReader(),
        pathReader: PathReading = PathReader(),
        session: URLSession = .reachabilitySession,
        pollInterval: TimeInterval = 1.0
    ) {
        self.systemConfig = systemConfig
        self.interfaceReader = interfaceReader
        self.wifiReader = wifiReader
        self.pathReader = pathReader
        self.session = session
        self.pollInterval = pollInterval
    }

    // MARK: - Fetch

    /// Reads all four readers (system config, interface, Wi-Fi, path) plus the
    /// public IPv6 lookup and publishes one assembled `ConnectionDetails`. Called on
    /// first expand and by `refresh()`.
    func fetchDetails() async {
        let scSnapshot = systemConfig.snapshot()

        // Fetch the public IPv6 and the one-shot NWPath concurrently with the
        // local (synchronous) reads.
        async let publicIPv6 = fetchPublicIPv6()
        async let pathSnapshot = pathReader.snapshot(excluding: scSnapshot.primaryInterface)

        var interfaceSnapshot = InterfaceSnapshot()
        var wifiSnapshot: WifiSnapshot?
        if let bsdName = scSnapshot.primaryInterface {
            interfaceSnapshot = interfaceReader.snapshot(for: bsdName)
            wifiSnapshot = wifiReader.snapshot(for: bsdName)
        }

        let resolvedPublicIPv6 = await publicIPv6
        let resolvedPath = await pathSnapshot

        // A cancelled fetch (popover closed mid-expand) must not publish a
        // half-fetched snapshot: `details != nil` would block the retry on the
        // next expand and silently lose the public IPv6 row.
        guard !Task.isCancelled else { return }

        details = ConnectionDetails(
            interface: .init(
                bsdName: scSnapshot.primaryInterface,
                displayName: scSnapshot.primaryInterfaceDisplayName,
                macAddress: interfaceSnapshot.macAddress,
                bssid: wifiSnapshot?.bssid,
                mtu: interfaceSnapshot.mtu,
                linkSpeedMbps: interfaceSnapshot.linkSpeedMbps,
                mediaDescription: interfaceSnapshot.mediaDescription,
                supports: Self.supportsText(resolvedPath),
                otherInterfaces: resolvedPath.otherInterfaces
            ),
            addressing: .init(
                ipv6Address: interfaceSnapshot.ipv6Address,
                publicIPv6: resolvedPublicIPv6,
                subnetMask: scSnapshot.subnetMask,
                routerAddress: scSnapshot.routerAddress,
                hostname: scSnapshot.hostname,
                ipv6Router: scSnapshot.ipv6Router,
                broadcastAddress: interfaceSnapshot.broadcastAddress,
                ipv4ConfigMethod: scSnapshot.ipv4ConfigMethod,
                computerName: scSnapshot.computerName
            ),
            dnsDhcp: .init(
                dnsServers: scSnapshot.dnsServers,
                searchDomains: scSnapshot.searchDomains,
                dhcpServer: scSnapshot.dhcpServer,
                dhcpLeaseStart: scSnapshot.dhcpLeaseStart,
                dhcpLeaseExpiry: scSnapshot.dhcpLeaseExpiry
            ),
            proxy: .init(
                httpProxy: scSnapshot.proxies.http,
                httpsProxy: scSnapshot.proxies.https,
                socksProxy: scSnapshot.proxies.socks
            ),
            wifi: wifiSnapshot.map(Self.wifiGroup)
        )
    }

    /// Composes the NWPath capability list ("IPv4 · IPv6 · DNS") from a path
    /// snapshot: only flags that are `true` are listed; all-false yields "None";
    /// all-nil (an empty/timed-out snapshot) yields nil so the row is omitted.
    static func supportsText(_ path: PathSnapshot) -> String? {
        let flags: [(Bool?, String)] = [
            (path.supportsIPv4, "IPv4"),
            (path.supportsIPv6, "IPv6"),
            (path.supportsDNS, "DNS")
        ]
        guard flags.contains(where: { $0.0 != nil }) else { return nil }
        let enabled = flags.compactMap { flag, label in flag == true ? label : nil }
        return enabled.isEmpty ? "None" : enabled.joined(separator: " · ")
    }

    /// Re-fetches the static details, but only once the dropdown has been opened
    /// at least once (`details != nil`). Wired into the existing refresh button.
    func refresh() async {
        guard details != nil else { return }
        await fetchDetails()
    }

    // MARK: - Connection change

    /// Invalidates the cached details when the active connection changes so an
    /// open dropdown stops showing the previous interface's fields. 
    func connectionChanged() {
        guard details != nil else { return }
        details = nil
        previousSample = nil
        changeTask?.cancel()
        changeTask = Task { await fetchDetails() }
    }

    /// Subscribes to network-stats changes so `connectionChanged()` fires on
    /// every connection switch (Wi-Fi → Ethernet, Wi-Fi A → Wi-Fi B). Idempotent:
    /// repeated calls (e.g. on every popover appearance) subscribe only once.
    func observeConnectionChanges(_ publisher: AnyPublisher<NetworkStats, Never>) {
        guard connectionChangeCancellable == nil else { return }
        connectionChangeCancellable = publisher.sink { [weak self] _ in
            self?.connectionChanged()
        }
    }

    // MARK: - Live polling

    /// Starts polling live metrics every `pollInterval`. The first tick publishes
    /// RF values with nil throughput (no prior counter sample yet); subsequent
    /// ticks add throughput. No-op if already live.
    func startLive() {
        guard !isLive else { return }
        isLive = true
        previousSample = nil
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    /// Stops polling, cancels the loop, and clears live state.
    func stopLive() {
        liveTask?.cancel()
        liveTask = nil
        isLive = false
        liveStats = nil
        previousSample = nil
    }

    /// Reads one live sample: byte/packet/error/drop counters (→ per-second rates
    /// vs the previous tick) and the Wi-Fi RF snapshot. Guards on a known primary
    /// interface. Rates stay nil until a second sample exists.
    private func tick() {
        guard let bsdName = details?.interface.bsdName else { return }

        let interfaceSnapshot = interfaceReader.snapshot(for: bsdName)
        let wifiSnapshot = wifiReader.snapshot(for: bsdName)

        let now = Date()
        let current = Self.counterSample(from: interfaceSnapshot, at: now)

        var download, upload, downloadPackets, uploadPackets, errors, drops: Double?
        if let previous = previousSample, let current {
            let elapsed = now.timeIntervalSince(previous.at)
            download = Self.bytesPerSecond(previous: previous.rxBytes, current: current.rxBytes, elapsed: elapsed)
            upload = Self.bytesPerSecond(previous: previous.txBytes, current: current.txBytes, elapsed: elapsed)
            downloadPackets = Self.bytesPerSecond(previous: previous.rxPackets, current: current.rxPackets, elapsed: elapsed)
            uploadPackets = Self.bytesPerSecond(previous: previous.txPackets, current: current.txPackets, elapsed: elapsed)
            errors = Self.bytesPerSecond(previous: previous.errors, current: current.errors, elapsed: elapsed)
            drops = Self.bytesPerSecond(previous: previous.drops, current: current.drops, elapsed: elapsed)
        }
        if let current { previousSample = current }

        liveStats = LiveConnectionStats(
            downloadBytesPerSec: download,
            uploadBytesPerSec: upload,
            downloadPacketsPerSec: downloadPackets,
            uploadPacketsPerSec: uploadPackets,
            errorsPerSec: errors,
            dropsPerSec: drops,
            rssiDBm: wifiSnapshot?.rssiDBm,
            noiseDBm: wifiSnapshot?.noiseDBm,
            txRateMbps: wifiSnapshot?.txRateMbps
        )
    }

    /// Builds a `CounterSample` from an interface snapshot, or nil if any counter
    /// is missing (all come from the same `if_data64` read, so it is all-or-nothing).
    private static func counterSample(from snapshot: InterfaceSnapshot, at date: Date) -> CounterSample? {
        guard let rxBytes = snapshot.rxBytes, let txBytes = snapshot.txBytes,
              let rxPackets = snapshot.rxPackets, let txPackets = snapshot.txPackets,
              let inErrors = snapshot.inErrors, let outErrors = snapshot.outErrors,
              let drops = snapshot.drops else {
            return nil
        }
        return CounterSample(
            rxBytes: rxBytes, txBytes: txBytes,
            rxPackets: rxPackets, txPackets: txPackets,
            errors: inErrors &+ outErrors, drops: drops, at: date
        )
    }

    /// Computes a per-second rate from two counter samples. Returns nil on a
    /// non-positive elapsed time or a counter reset (current < previous).
    static func bytesPerSecond(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double? {
        guard elapsed > 0, current >= previous else { return nil }
        return Double(current - previous) / elapsed
    }

    // MARK: - Helpers

    /// Maps a `WifiSnapshot` to the model's Wi-Fi group.
    private static func wifiGroup(_ snapshot: WifiSnapshot) -> ConnectionDetails.Wifi {
        ConnectionDetails.Wifi(
            channelNumber: snapshot.channelNumber,
            band: snapshot.band,
            channelWidthMHz: snapshot.channelWidthMHz,
            phyMode: snapshot.phyMode,
            mode: snapshot.interfaceMode,
            txPowerMw: snapshot.txPowerMw,
            security: snapshot.security,
            countryCode: snapshot.countryCode
        )
    }

    /// Fetches the device's public IPv6 via `api6.ipify.org`. Returns nil on any
    /// failure, a non-2xx status, or a body that isn't an IPv6 literal (no colon)
    /// — common when the network has no IPv6 connectivity.
    private func fetchPublicIPv6() async -> String? {
        let url = URL(string: "https://api6.ipify.org")!
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            guard let body = String(data: data, encoding: .utf8), body.contains(":") else {
                return nil
            }
            return body
        } catch {
            return nil
        }
    }

    deinit {
        liveTask?.cancel()
        changeTask?.cancel()
    }
}

// Not #if DEBUG-guarded: #Preview bodies compile in Release too, and the
// existing mock convention (NetworkStats.mock*) ships unguarded as well.
extension ConnectionDetailsManager {
    /// Applies fixed state without consulting the readers — used by SwiftUI
    /// previews and the `--demo` screenshot mode. With `isLive` true the Live
    /// section shows `liveStats` as-is; no polling loop runs.
    func apply(
        details: ConnectionDetails?,
        isLive: Bool = false,
        liveStats: LiveConnectionStats? = nil
    ) {
        self.details = details
        self.isLive = isLive
        self.liveStats = liveStats
    }

    /// Builds a manager pre-populated with static state for SwiftUI previews.
    /// No fetch is performed and the real readers are never consulted.
    static func preview(
        details: ConnectionDetails?,
        isLive: Bool = false,
        liveStats: LiveConnectionStats? = nil
    ) -> ConnectionDetailsManager {
        let manager = ConnectionDetailsManager()
        manager.apply(details: details, isLive: isLive, liveStats: liveStats)
        return manager
    }
}
