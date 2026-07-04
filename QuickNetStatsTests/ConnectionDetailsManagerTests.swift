//
//  ConnectionDetailsManagerTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

// MARK: - Reader test doubles

/// Reference-type reader stubs so tests can observe call counts across `fetch`/`refresh`.
final class MockSystemConfigReader: SystemConfigReading {
    var result: SystemConfigSnapshot
    private(set) var callCount = 0
    init(result: SystemConfigSnapshot) { self.result = result }
    func snapshot() -> SystemConfigSnapshot {
        callCount += 1
        return result
    }
}

final class MockInterfaceReader: InterfaceReading {
    var result: InterfaceSnapshot
    /// When > 0, rx/tx byte counters grow by this amount on each call so live
    /// polling can compute a positive throughput delta (used by Task 7 tests).
    var incrementPerCall: UInt64 = 0
    private(set) var callCount = 0
    init(result: InterfaceSnapshot) { self.result = result }
    func snapshot(for bsdName: String) -> InterfaceSnapshot {
        callCount += 1
        guard incrementPerCall > 0 else { return result }
        var snapshot = result
        snapshot.rxBytes = (result.rxBytes ?? 0) + incrementPerCall * UInt64(callCount)
        snapshot.txBytes = (result.txBytes ?? 0) + incrementPerCall * UInt64(callCount)
        return snapshot
    }
}

final class MockWifiReader: WifiReading {
    var result: WifiSnapshot?
    private(set) var callCount = 0
    init(result: WifiSnapshot?) { self.result = result }
    func snapshot(for bsdName: String) -> WifiSnapshot? {
        callCount += 1
        return result
    }
}

@Suite("ConnectionDetailsManager", .serialized)
struct ConnectionDetailsManagerTests {

    // MARK: - Fixtures

    private var fullSystemConfig: SystemConfigSnapshot {
        SystemConfigSnapshot(
            primaryInterface: "en0",
            primaryInterfaceDisplayName: "Wi-Fi",
            primaryService: "SERVICE-ID",
            routerAddress: "192.168.1.1",
            dnsServers: ["1.1.1.1"],
            searchDomains: ["home"],
            subnetMask: "255.255.255.0",
            dhcpLeaseExpiry: nil,
            hostname: "mac"
        )
    }

    private var fullInterface: InterfaceSnapshot {
        InterfaceSnapshot(
            macAddress: "aa:bb:cc:dd:ee:ff",
            mtu: 1500,
            ipv6Address: "2a00::1",
            linkSpeedMbps: 866,
            rxBytes: 1_000,
            txBytes: 500
        )
    }

    private var fullWifi: WifiSnapshot {
        WifiSnapshot(
            channelNumber: 44,
            band: "5 GHz",
            channelWidthMHz: 80,
            phyMode: "802.11ax",
            security: "WPA3 Personal",
            countryCode: "IT",
            rssiDBm: -52,
            noiseDBm: -95,
            txRateMbps: 866
        )
    }

    /// Builds a session that routes ipify requests through the given handler.
    private func mockSession(_ handler: @escaping MockURLProtocol.Handler) -> URLSession {
        MockURLProtocol.requestHandler = handler
        let config = URLSessionConfiguration.ephemeral
        let token = UUID().uuidString
        config.httpAdditionalHeaders = [MockURLProtocol.tokenHeader: token]
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handlers[token] = MockURLProtocol.requestHandler
        return URLSession(configuration: config)
    }

    /// A handler that returns 200 with the given body.
    private func ok(_ body: String) -> MockURLProtocol.Handler {
        { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    // MARK: - Fetch assembly

    @Test("fetch assembles all four groups from the reader stubs")
    func fetchAssemblesGroups() async {
        let systemConfig = MockSystemConfigReader(result: fullSystemConfig)
        let interfaceReader = MockInterfaceReader(result: fullInterface)
        let wifiReader = MockWifiReader(result: fullWifi)

        let manager = ConnectionDetailsManager(
            systemConfig: systemConfig,
            interfaceReader: interfaceReader,
            wifiReader: wifiReader,
            session: mockSession(ok("2a00::1")),
            pollInterval: 0.05
        )

        await manager.fetchDetails()

        let details = manager.details
        #expect(details?.interface.macAddress == "aa:bb:cc:dd:ee:ff")
        #expect(details?.interface.displayName == "Wi-Fi")
        #expect(details?.interface.bsdName == "en0")
        #expect(details?.addressing.routerAddress == "192.168.1.1")
        #expect(details?.addressing.ipv6Address == "2a00::1")
        #expect(details?.dnsDhcp.dnsServers == ["1.1.1.1"])
        #expect(details?.wifi?.channelNumber == 44)
        #expect(details?.wifi?.security == "WPA3 Personal")
    }

    @Test("a nil Wi-Fi reader result leaves the Wi-Fi group nil")
    func nilWifiReaderLeavesGroupNil() async {
        let manager = ConnectionDetailsManager(
            systemConfig: MockSystemConfigReader(result: fullSystemConfig),
            interfaceReader: MockInterfaceReader(result: fullInterface),
            wifiReader: MockWifiReader(result: nil),
            session: mockSession(ok("2a00::1"))
        )

        await manager.fetchDetails()

        #expect(manager.details?.wifi == nil)
        #expect(manager.details?.wifiRows.isEmpty == true)
    }

    // MARK: - Public IPv6

    @Test("a 200 IPv6 body populates publicIPv6")
    func publicIPv6Populated() async {
        let manager = ConnectionDetailsManager(
            systemConfig: MockSystemConfigReader(result: fullSystemConfig),
            interfaceReader: MockInterfaceReader(result: fullInterface),
            wifiReader: MockWifiReader(result: nil),
            session: mockSession(ok("2a01:e11::1"))
        )

        await manager.fetchDetails()

        #expect(manager.details?.addressing.publicIPv6 == "2a01:e11::1")
    }

    @Test("a server error leaves publicIPv6 nil")
    func publicIPv6NilOnServerError() async {
        let handler: MockURLProtocol.Handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let manager = ConnectionDetailsManager(
            systemConfig: MockSystemConfigReader(result: fullSystemConfig),
            interfaceReader: MockInterfaceReader(result: fullInterface),
            wifiReader: MockWifiReader(result: nil),
            session: mockSession(handler)
        )

        await manager.fetchDetails()

        #expect(manager.details?.addressing.publicIPv6 == nil)
    }

    @Test("a network error leaves publicIPv6 nil")
    func publicIPv6NilOnNetworkError() async {
        let handler: MockURLProtocol.Handler = { _ in throw URLError(.notConnectedToInternet) }
        let manager = ConnectionDetailsManager(
            systemConfig: MockSystemConfigReader(result: fullSystemConfig),
            interfaceReader: MockInterfaceReader(result: fullInterface),
            wifiReader: MockWifiReader(result: nil),
            session: mockSession(handler)
        )

        await manager.fetchDetails()

        #expect(manager.details?.addressing.publicIPv6 == nil)
    }

    @Test("a 200 response without a colon is not treated as an IPv6 address")
    func publicIPv6NilWhenBodyNotV6() async {
        let manager = ConnectionDetailsManager(
            systemConfig: MockSystemConfigReader(result: fullSystemConfig),
            interfaceReader: MockInterfaceReader(result: fullInterface),
            wifiReader: MockWifiReader(result: nil),
            session: mockSession(ok("not-an-address"))
        )

        await manager.fetchDetails()

        #expect(manager.details?.addressing.publicIPv6 == nil)
    }

    // MARK: - No primary interface

    @Test("fetch still publishes router/DNS when there is no primary interface")
    func fetchWithoutPrimaryInterface() async {
        var systemConfig = fullSystemConfig
        systemConfig.primaryInterface = nil
        systemConfig.primaryInterfaceDisplayName = nil

        let interfaceReader = MockInterfaceReader(result: fullInterface)
        let wifiReader = MockWifiReader(result: fullWifi)

        let manager = ConnectionDetailsManager(
            systemConfig: MockSystemConfigReader(result: systemConfig),
            interfaceReader: interfaceReader,
            wifiReader: wifiReader,
            session: mockSession(ok("2a00::1"))
        )

        await manager.fetchDetails()

        #expect(manager.details != nil)
        #expect(manager.details?.addressing.routerAddress == "192.168.1.1")
        #expect(manager.details?.dnsDhcp.dnsServers == ["1.1.1.1"])
        // With no BSD name the interface/Wi-Fi readers are never consulted.
        #expect(interfaceReader.callCount == 0)
        #expect(wifiReader.callCount == 0)
        #expect(manager.details?.wifi == nil)
    }

    // MARK: - Refresh

    @Test("refresh is a no-op before the first fetch")
    func refreshNoOpBeforeFetch() async {
        let systemConfig = MockSystemConfigReader(result: fullSystemConfig)
        let manager = ConnectionDetailsManager(
            systemConfig: systemConfig,
            interfaceReader: MockInterfaceReader(result: fullInterface),
            wifiReader: MockWifiReader(result: nil),
            session: mockSession(ok("2a00::1"))
        )

        await manager.refresh()

        #expect(manager.details == nil)
        #expect(systemConfig.callCount == 0)
    }

    @Test("refresh re-fetches after the first fetch")
    func refreshRefetchesAfterFetch() async {
        let systemConfig = MockSystemConfigReader(result: fullSystemConfig)
        let manager = ConnectionDetailsManager(
            systemConfig: systemConfig,
            interfaceReader: MockInterfaceReader(result: fullInterface),
            wifiReader: MockWifiReader(result: nil),
            session: mockSession(ok("2a00::1"))
        )

        await manager.fetchDetails()
        await manager.refresh()

        #expect(systemConfig.callCount == 2)
    }

    // MARK: - Live polling

    /// Polls `condition` until it is true or the timeout elapses, yielding the
    /// main actor between checks so the manager's poll loop can advance.
    @discardableResult
    private func eventually(
        timeout: Duration = .seconds(3),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Builds a manager whose interface reader grows its counters each call so
    /// the poll loop produces a positive throughput delta.
    private func liveManager(pollInterval: TimeInterval) -> ConnectionDetailsManager {
        let interfaceReader = MockInterfaceReader(result: fullInterface)
        interfaceReader.incrementPerCall = 1_000
        return ConnectionDetailsManager(
            systemConfig: MockSystemConfigReader(result: fullSystemConfig),
            interfaceReader: interfaceReader,
            wifiReader: MockWifiReader(result: fullWifi),
            session: mockSession(ok("2a00::1")),
            pollInterval: pollInterval
        )
    }

    @Test("bytesPerSecond computes deltas and rejects resets and zero elapsed")
    func bytesPerSecondMath() {
        #expect(ConnectionDetailsManager.bytesPerSecond(previous: 1_000, current: 3_000, elapsed: 2.0) == 1_000)
        #expect(ConnectionDetailsManager.bytesPerSecond(previous: 3_000, current: 1_000, elapsed: 2.0) == nil)
        #expect(ConnectionDetailsManager.bytesPerSecond(previous: 1_000, current: 3_000, elapsed: 0) == nil)
    }

    @Test("the first tick publishes RF values with no throughput")
    func firstTickHasRFOnly() async {
        // An interval far beyond the eventually-timeout guarantees the second tick
        // can never fire during this test, even under heavy CI load; stopLive()
        // cancels the sleep so the test still finishes immediately.
        let manager = liveManager(pollInterval: 60)
        await manager.fetchDetails()
        manager.startLive()

        let gotRSSI = await eventually { manager.liveStats?.rssiDBm != nil }
        #expect(gotRSSI)
        #expect(manager.liveStats?.rssiDBm == -52)
        #expect(manager.liveStats?.downloadBytesPerSec == nil)

        manager.stopLive()
    }

    @Test("throughput appears from the second tick onward")
    func throughputOnSecondTick() async {
        let manager = liveManager(pollInterval: 0.05)
        await manager.fetchDetails()
        manager.startLive()

        let gotThroughput = await eventually { manager.liveStats?.downloadBytesPerSec != nil }
        #expect(gotThroughput)
        #expect(manager.liveStats?.uploadBytesPerSec != nil)
        #expect(manager.liveStats?.rssiDBm == -52)

        manager.stopLive()
    }

    @Test("startLive without a prior fetch is safe and publishes nothing")
    func startLiveWithoutFetchIsSafe() async {
        let manager = ConnectionDetailsManager(
            systemConfig: MockSystemConfigReader(result: fullSystemConfig),
            interfaceReader: MockInterfaceReader(result: fullInterface),
            wifiReader: MockWifiReader(result: fullWifi),
            session: mockSession(ok("2a00::1")),
            pollInterval: 0.05
        )

        manager.startLive()
        #expect(manager.isLive)
        // tick() guards on details.bsdName, so nothing is published without a fetch.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(manager.liveStats == nil)

        manager.stopLive()
        #expect(manager.isLive == false)
    }

    @Test("stopLive cancels the loop and clears state")
    func stopLiveClearsState() async {
        let manager = liveManager(pollInterval: 0.05)
        await manager.fetchDetails()
        manager.startLive()

        _ = await eventually { manager.liveStats != nil }
        #expect(manager.isLive)

        manager.stopLive()
        #expect(manager.isLive == false)
        #expect(manager.liveStats == nil)
    }

    @Test("a second startLive does not stack a second poll loop")
    func doubleStartDoesNotStack() async {
        let manager = liveManager(pollInterval: 0.05)
        await manager.fetchDetails()

        manager.startLive()
        manager.startLive()   // guarded no-op

        _ = await eventually { manager.liveStats != nil }
        manager.stopLive()

        #expect(manager.isLive == false)
        #expect(manager.liveStats == nil)
        // A leaked/stacked task would keep publishing after stop; it must stay nil.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(manager.liveStats == nil)
    }
}
