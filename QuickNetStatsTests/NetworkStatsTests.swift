//
//  NetworkStatsTests.swift
//  QuickNetStatsTests
//
//  Tests for NetworkStats model: computed properties, summaries, and static mocks.
//

import Testing
@testable import QuickNetStats

@Suite("NetworkStats Model")
struct NetworkStatsTests {

    // MARK: - isConnected

    @Test("isConnected returns true when status is satisfied")
    func connectedWhenSatisfied() {
        let stats = NetworkStats.mockGoodWifiConnection
        #expect(stats.isConnected)
    }

    @Test("isConnected returns false when disconnected")
    func disconnectedWhenUnsatisfied() {
        let stats = NetworkStats.mockDisconnected
        #expect(!stats.isConnected)
    }

    // MARK: - shortSummary

    @Test("shortSummary shows 'No Connection' when interface is none")
    func shortSummaryNoConnection() {
        let stats = NetworkStats.mockDisconnected
        #expect(stats.shortSummary == "No Connection")
    }

    @Test(
        "shortSummary shows interface type for connected stats",
        arguments: [
            (NetworkStats.mockGoodWifiConnection, "Wifi Connection"),
            (NetworkStats.mockGoodEthConnection, "Ethernet Connection"),
            (NetworkStats.mockExpensiveCellConnection, "Cellular Connection"),
        ]
    )
    func shortSummaryConnected(stats: NetworkStats, expected: String) {
        #expect(stats.shortSummary == expected)
    }

    // MARK: - fullSummary

    @Test("fullSummary equals shortSummary when interface is none")
    func fullSummaryNoConnection() {
        let stats = NetworkStats.mockDisconnected
        #expect(stats.fullSummary == stats.shortSummary)
    }

    // MARK: - Interface type classification

    @Test("WiFi interface is correctly identified")
    func wifiInterface() {
        let stats = NetworkStats.mockGoodWifiConnection
        #expect(stats.interfaceType == .wifi)
        #expect(stats.connectionTechnology == .wifi)
    }

    @Test("Ethernet interface is correctly identified")
    func ethernetInterface() {
        let stats = NetworkStats.mockGoodEthConnection
        #expect(stats.interfaceType == .ethernet)
        #expect(stats.connectionTechnology == .wiredEthernet)
    }

    @Test("Expensive WiFi is reclassified as cellular (hotspot)")
    func hotspotWifiReclassified() {
        let stats = NetworkStats.mockExpensiveCellConnection
        #expect(stats.interfaceType == .cellular)
        #expect(stats.isExpensive)
    }

    @Test("Constrained connection is detected")
    func constrainedDetected() {
        let stats = NetworkStats.mockConstrainedWifiConnection
        #expect(stats.isConstrained)
    }

    @Test("Constrained and expensive connection detected")
    func constrainedAndExpensive() {
        let stats = NetworkStats.mockConstrainedExpensiveCellConnection
        #expect(stats.isConstrained)
        #expect(stats.isExpensive)
        #expect(stats.interfaceType == .cellular)
    }

    // MARK: - Link quality

    @Test(
        "Link quality is set correctly on mocks",
        arguments: [
            (NetworkStats.mockGoodWifiConnection, LinkQuality.good),
            (NetworkStats.mockModerateWifiConnection, LinkQuality.moderate),
            (NetworkStats.mockBadWifiConnection, LinkQuality.minimal),
            (NetworkStats.mockDisconnected, LinkQuality.unknown),
        ]
    )
    func linkQualityValues(stats: NetworkStats, expectedQuality: LinkQuality) {
        #expect(stats.linkQuality == expectedQuality)
    }

    // MARK: - defaultOffline

    @Test("defaultOffline has expected disconnected state")
    func defaultOfflineState() {
        let stats = NetworkStats.defaultOffline
        #expect(!stats.isConnected)
        #expect(stats.interfaceType == .none)
        #expect(!stats.isExpensive)
        #expect(!stats.isConstrained)
        #expect(stats.linkQuality == .unknown)
    }
}
