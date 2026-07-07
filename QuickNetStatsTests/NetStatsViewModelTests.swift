//
//  NetStatsViewModelTests.swift
//  QuickNetStatsTests
//
//  Tests for NetStatsViewModel: link quality color mapping.
//

import Testing
import SwiftUI
@testable import QuickNetStats

@Suite("NetStatsViewModel")
struct NetStatsViewModelTests {

    // MARK: - Link quality color

    @Test(
        "linkQualityColor maps quality to correct color",
        arguments: [
            (NetworkStats.mockGoodWifiConnection, Color.green),
            (NetworkStats.mockModerateWifiConnection, Color.orange),
            (NetworkStats.mockBadWifiConnection, Color.red),
            (NetworkStats.mockDisconnected, Color.secondary),
        ]
    )
    func linkQualityColorMapping(stats: NetworkStats, expected: Color) {
        let vm = NetStatsViewModel(netStats: stats, privateIP: nil, publicIP: nil)
        #expect(vm.linkQualityColor == expected)
    }

    // MARK: - Wi-Fi connection gate

    @Test(
        "isWifiConnection is true only when the connection rides Wi-Fi",
        arguments: [
            (NetworkStats.mockGoodWifiConnection, true),
            (NetworkStats.mockGoodEthConnection, false),
            (NetworkStats.mockConstrainedExpensiveCellConnection, true),   // hotspot over Wi-Fi
            (NetworkStats.mockExpensiveCellConnection, false),             // hotspot over cable
            (NetworkStats.mockDisconnected, false),
        ]
    )
    func isWifiConnectionGate(netStats: NetworkStats, expected: Bool) {
        let vm = NetStatsViewModel(netStats: netStats, privateIP: nil, publicIP: nil)
        #expect(vm.isWifiConnection == expected)
    }

    // MARK: - Initialization

    @Test("ViewModel stores IP addresses")
    func storesIPs() {
        let vm = NetStatsViewModel(
            netStats: NetworkStats.mockGoodWifiConnection,
            privateIP: "192.168.1.1",
            publicIP: "8.8.8.8"
        )
        #expect(vm.privateIP == "192.168.1.1")
        #expect(vm.publicIP == "8.8.8.8")
    }

    @Test("ViewModel handles nil IP addresses")
    func nilIPs() {
        let vm = NetStatsViewModel(
            netStats: NetworkStats.mockDisconnected,
            privateIP: nil,
            publicIP: nil
        )
        #expect(vm.privateIP == nil)
        #expect(vm.publicIP == nil)
    }
}
