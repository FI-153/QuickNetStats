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
    private let session: URLSession
    private let pollInterval: TimeInterval

    /// The running poll loop, if any.
    private var liveTask: Task<Void, Never>?

    /// A byte-counter sample taken at a point in time, used to compute deltas.
    private struct ByteSample {
        let rx: UInt64
        let tx: UInt64
        let at: Date
    }

    /// The previous throughput sample, used to compute per-second deltas.
    private var previousSample: ByteSample?

    // MARK: - Initializer

    init(
        systemConfig: SystemConfigReading = SystemConfigReader(),
        interfaceReader: InterfaceReading = InterfaceReader(),
        wifiReader: WifiReading = WifiReader(),
        session: URLSession = .reachabilitySession,
        pollInterval: TimeInterval = 1.0
    ) {
        self.systemConfig = systemConfig
        self.interfaceReader = interfaceReader
        self.wifiReader = wifiReader
        self.session = session
        self.pollInterval = pollInterval
    }

    // MARK: - Fetch

    /// Reads all three readers plus the public IPv6 lookup and publishes one
    /// assembled `ConnectionDetails`. Called on first expand and by `refresh()`.
    func fetchDetails() async {
        let scSnapshot = systemConfig.snapshot()

        // Fetch the public IPv6 concurrently with the local (synchronous) reads.
        async let publicIPv6 = fetchPublicIPv6()

        var interfaceSnapshot = InterfaceSnapshot()
        var wifiSnapshot: WifiSnapshot?
        if let bsdName = scSnapshot.primaryInterface {
            interfaceSnapshot = interfaceReader.snapshot(for: bsdName)
            wifiSnapshot = wifiReader.snapshot(for: bsdName)
        }

        let resolvedPublicIPv6 = await publicIPv6

        // A cancelled fetch (popover closed mid-expand) must not publish a
        // half-fetched snapshot: `details != nil` would block the retry on the
        // next expand and silently lose the public IPv6 row.
        guard !Task.isCancelled else { return }

        details = ConnectionDetails(
            interface: .init(
                bsdName: scSnapshot.primaryInterface,
                displayName: scSnapshot.primaryInterfaceDisplayName,
                macAddress: interfaceSnapshot.macAddress,
                mtu: interfaceSnapshot.mtu,
                linkSpeedMbps: interfaceSnapshot.linkSpeedMbps
            ),
            addressing: .init(
                ipv6Address: interfaceSnapshot.ipv6Address,
                publicIPv6: resolvedPublicIPv6,
                subnetMask: scSnapshot.subnetMask,
                routerAddress: scSnapshot.routerAddress,
                hostname: scSnapshot.hostname
            ),
            dnsDhcp: .init(
                dnsServers: scSnapshot.dnsServers,
                searchDomains: scSnapshot.searchDomains,
                dhcpLeaseExpiry: scSnapshot.dhcpLeaseExpiry
            ),
            wifi: wifiSnapshot.map(Self.wifiGroup)
        )
    }

    /// Re-fetches the static details, but only once the dropdown has been opened
    /// at least once (`details != nil`). Wired into the existing refresh button.
    func refresh() async {
        guard details != nil else { return }
        await fetchDetails()
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

    /// Reads one live sample: byte counters (→ throughput vs the previous tick)
    /// and the Wi-Fi RF snapshot. Guards on a known primary interface.
    private func tick() {
        guard let bsdName = details?.interface.bsdName else { return }

        let interfaceSnapshot = interfaceReader.snapshot(for: bsdName)
        let wifiSnapshot = wifiReader.snapshot(for: bsdName)

        let now = Date()
        var download: Double?
        var upload: Double?
        if let previous = previousSample,
           let rx = interfaceSnapshot.rxBytes,
           let tx = interfaceSnapshot.txBytes {
            let elapsed = now.timeIntervalSince(previous.at)
            download = Self.bytesPerSecond(previous: previous.rx, current: rx, elapsed: elapsed)
            upload = Self.bytesPerSecond(previous: previous.tx, current: tx, elapsed: elapsed)
        }
        if let rx = interfaceSnapshot.rxBytes, let tx = interfaceSnapshot.txBytes {
            previousSample = ByteSample(rx: rx, tx: tx, at: now)
        }

        liveStats = LiveConnectionStats(
            downloadBytesPerSec: download,
            uploadBytesPerSec: upload,
            rssiDBm: wifiSnapshot?.rssiDBm,
            noiseDBm: wifiSnapshot?.noiseDBm,
            txRateMbps: wifiSnapshot?.txRateMbps
        )
    }

    /// Computes a per-second byte rate from two counter samples. Returns nil on a
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
    }
}

#if DEBUG
extension ConnectionDetailsManager {
    /// Builds a manager pre-populated with static state for SwiftUI previews.
    /// No fetch is performed and the real readers are never consulted.
    static func preview(
        details: ConnectionDetails?,
        isLive: Bool = false,
        liveStats: LiveConnectionStats? = nil
    ) -> ConnectionDetailsManager {
        let manager = ConnectionDetailsManager()
        manager.details = details
        manager.isLive = isLive
        manager.liveStats = liveStats
        return manager
    }
}
#endif
