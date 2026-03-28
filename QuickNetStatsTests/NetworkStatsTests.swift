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
        let stats = NetworkStats.mockGoodWifiCoonection
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
            (NetworkStats.mockGoodWifiCoonection, "Wifi Connection"),
            (NetworkStats.mockGoodEthCoonection, "Ethernet Connection"),
            (NetworkStats.mockExpansiveCellCoonection, "Cellular Connection"),
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
        let stats = NetworkStats.mockGoodWifiCoonection
        #expect(stats.interfaceType == .wifi)
        #expect(stats.connectionTechnology == .wifi)
    }

    @Test("Ethernet interface is correctly identified")
    func ethernetInterface() {
        let stats = NetworkStats.mockGoodEthCoonection
        #expect(stats.interfaceType == .ethernet)
        #expect(stats.connectionTechnology == .wiredEthernet)
    }

    @Test("Expensive WiFi is reclassified as cellular (hotspot)")
    func hotspotWifiReclassified() {
        let stats = NetworkStats.mockExpansiveCellCoonection
        #expect(stats.interfaceType == .cellular)
        #expect(stats.isExpensive)
    }

    @Test("Constrained connection is detected")
    func constrainedDetected() {
        let stats = NetworkStats.mockConstrainedWifiCoonection
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
            (NetworkStats.mockGoodWifiCoonection, LinkQuality.good),
            (NetworkStats.mockModerateWifiCoonection, LinkQuality.moderate),
            (NetworkStats.mockBadWifiCoonection, LinkQuality.minimal),
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
