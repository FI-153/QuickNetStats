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
            (NetworkStats.mockGoodWifiCoonection, Color.green),
            (NetworkStats.mockModerateWifiCoonection, Color.orange),
            (NetworkStats.mockBadWifiCoonection, Color.red),
            (NetworkStats.mockDisconnected, Color.secondary),
        ]
    )
    func linkQualityColorMapping(stats: NetworkStats, expected: Color) {
        let vm = NetStatsViewModel(netStats: stats, privateIP: nil, publicIP: nil)
        #expect(vm.linkQualityColor == expected)
    }

    // MARK: - Initialization

    @Test("ViewModel stores IP addresses")
    func storesIPs() {
        let vm = NetStatsViewModel(
            netStats: NetworkStats.mockGoodWifiCoonection,
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
