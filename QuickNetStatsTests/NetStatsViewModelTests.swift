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

    // MARK: - Monochrome tint

    @Test(
        "monochromeColor uses semantic hierarchy instead of a hard-coded color",
        arguments: [
            (ColorScheme.light, Color.primary),
            (ColorScheme.dark, Color.secondary),
        ]
    )
    func monochromeColorMapping(colorScheme: ColorScheme, expected: Color) {
        #expect(NetStatsViewModel.monochromeColor(for: colorScheme) == expected)
    }

    // MARK: - Accessibility summary

    @Test(
        "accessibilitySummary speaks interface, SSID, and link quality",
        arguments: [
            (NetworkStats.mockGoodWifiConnection, true, "Wi-Fi, HomeNet, link quality Good"),
            (NetworkStats.mockGoodWifiConnection, false, "Wi-Fi, link quality Good"),
            (NetworkStats.mockBadWifiConnection, true, "Wi-Fi, HomeNet, link quality Minimal"),
            (NetworkStats.mockGoodEthConnection, true, "Ethernet, link quality Good"),
            (NetworkStats.mockExpensiveCellConnection, true, "Personal Hotspot, link quality Good"),
            (NetworkStats.mockDisconnected, true, "Disconnected"),
        ]
    )
    func accessibilitySummary(netStats: NetworkStats, includeSSID: Bool, expected: String) {
        let vm = NetStatsViewModel(netStats: netStats, privateIP: nil, publicIP: nil, ssid: "HomeNet")
        #expect(vm.accessibilitySummary(includeSSID: includeSSID) == expected)
    }

    @Test("accessibilitySummary omits a missing SSID")
    func accessibilitySummaryWithoutSSID() {
        let vm = NetStatsViewModel(netStats: .mockGoodWifiConnection, privateIP: nil, publicIP: nil, ssid: nil)
        #expect(vm.accessibilitySummary(includeSSID: true) == "Wi-Fi, link quality Good")
    }

    @Test(
        "accessibilitySummary omits link quality when unavailable or still computing",
        arguments: [nil, LinkQuality.unknown] as [LinkQuality?]
    )
    func accessibilitySummaryWithoutQuality(linkQuality: LinkQuality?) {
        var stats = NetworkStats.mockGoodWifiConnection
        stats.linkQuality = linkQuality
        let vm = NetStatsViewModel(netStats: stats, privateIP: nil, publicIP: nil, ssid: "HomeNet")
        #expect(vm.accessibilitySummary(includeSSID: true) == "Wi-Fi, HomeNet")
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
