//
//  ConnectionDetailsTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

@Suite("ConnectionDetails")
struct ConnectionDetailsTests {

    /// Returns the value of the row with the given label, or nil if absent.
    private func value(_ label: String, in rows: [DetailRow]) -> String? {
        rows.first { $0.label == label }?.value
    }

    // MARK: - Interface group

    @Test("An empty interface produces no rows")
    func emptyInterfaceHasNoRows() {
        let details = ConnectionDetails(interface: .init())
        #expect(details.interfaceRows.isEmpty)
    }

    @Test("Name row composes displayName and bsdName")
    func nameComposesBoth() {
        let details = ConnectionDetails(interface: .init(bsdName: "en0", displayName: "Wi-Fi"))
        #expect(value("Name", in: details.interfaceRows) == "Wi-Fi (en0)")
    }

    @Test("Name row uses displayName alone when bsdName is nil")
    func nameDisplayNameOnly() {
        let details = ConnectionDetails(interface: .init(displayName: "Wi-Fi"))
        #expect(value("Name", in: details.interfaceRows) == "Wi-Fi")
    }

    @Test("Name row uses bsdName alone when displayName is nil")
    func nameBsdNameOnly() {
        let details = ConnectionDetails(interface: .init(bsdName: "en0"))
        #expect(value("Name", in: details.interfaceRows) == "en0")
    }

    @Test("Name row omitted when both names are nil")
    func nameOmittedWhenBothNil() {
        let details = ConnectionDetails(interface: .init(macAddress: "aa:bb:cc:dd:ee:ff"))
        #expect(value("Name", in: details.interfaceRows) == nil)
    }

    @Test("MAC address and MTU rows reflect their fields")
    func macAndMtuRows() {
        let details = ConnectionDetails(
            interface: .init(macAddress: "aa:bb:cc:dd:ee:ff", mtu: 1500)
        )
        #expect(value("MAC address", in: details.interfaceRows) == "aa:bb:cc:dd:ee:ff")
        #expect(value("MTU", in: details.interfaceRows) == "1500")
    }

    @Test("Link speed under 1000 renders as whole Mbps")
    func linkSpeedMbps() {
        let details = ConnectionDetails(interface: .init(linkSpeedMbps: 866))
        #expect(value("Link speed", in: details.interfaceRows) == "866 Mbps")
    }

    @Test("Link speed of 1000 renders as 1 Gbps with trailing zero stripped")
    func linkSpeedOneGbps() {
        let details = ConnectionDetails(interface: .init(linkSpeedMbps: 1000))
        #expect(value("Link speed", in: details.interfaceRows) == "1 Gbps")
    }

    @Test("Link speed of 2500 renders as 2.5 Gbps")
    func linkSpeedFractionalGbps() {
        let details = ConnectionDetails(interface: .init(linkSpeedMbps: 2500))
        #expect(value("Link speed", in: details.interfaceRows) == "2.5 Gbps")
    }

    // MARK: - Addressing group

    @Test("An empty addressing block produces no rows")
    func emptyAddressingHasNoRows() {
        let details = ConnectionDetails(addressing: .init())
        #expect(details.addressingRows.isEmpty)
    }

    @Test("Addressing rows appear in design order and omit nil fields")
    func addressingRowsOrderAndOmission() {
        let details = ConnectionDetails(
            addressing: .init(
                ipv6Address: "2a00::1",
                subnetMask: "255.255.255.0",
                routerAddress: "192.168.1.1",
                hostname: "mac"
            )
        )
        #expect(details.addressingRows.map(\.label) == [
            "Router", "Subnet mask", "IPv6 (local)", "Hostname"
        ])
        #expect(value("Public IPv6", in: details.addressingRows) == nil)
    }

    // MARK: - DNS & DHCP group

    @Test("DNS servers are comma-joined")
    func dnsJoined() {
        let details = ConnectionDetails(dnsDhcp: .init(dnsServers: ["1.1.1.1", "8.8.8.8"]))
        #expect(value("DNS servers", in: details.dnsDhcpRows) == "1.1.1.1, 8.8.8.8")
    }

    @Test("Empty DNS and search-domain arrays produce no rows")
    func emptyDnsArraysOmitted() {
        let details = ConnectionDetails(dnsDhcp: .init())
        #expect(value("DNS servers", in: details.dnsDhcpRows) == nil)
        #expect(value("Search domains", in: details.dnsDhcpRows) == nil)
    }

    @Test("Search domains are comma-joined")
    func searchDomainsJoined() {
        let details = ConnectionDetails(dnsDhcp: .init(searchDomains: ["home", "lan"]))
        #expect(value("Search domains", in: details.dnsDhcpRows) == "home, lan")
    }

    @Test("DHCP lease row present for a date, absent for nil")
    func dhcpLeaseRowPresence() {
        let withLease = ConnectionDetails(dnsDhcp: .init(dhcpLeaseExpiry: Date()))
        #expect(value("DHCP lease expires", in: withLease.dnsDhcpRows) != nil)

        let withoutLease = ConnectionDetails(dnsDhcp: .init())
        #expect(value("DHCP lease expires", in: withoutLease.dnsDhcpRows) == nil)
    }

    // MARK: - Wi-Fi group

    @Test("wifiRows is empty when wifi is nil")
    func wifiRowsEmptyWhenNil() {
        let details = ConnectionDetails()
        #expect(details.wifi == nil)
        #expect(details.wifiRows.isEmpty)
    }

    @Test("Channel row composes number, band, and width")
    func channelFullComposition() {
        let details = ConnectionDetails(
            wifi: .init(channelNumber: 44, band: "5 GHz", channelWidthMHz: 80)
        )
        #expect(value("Channel", in: details.wifiRows) == "44 · 5 GHz · 80 MHz")
    }

    @Test("Channel row drops nil pieces")
    func channelPartialComposition() {
        let details = ConnectionDetails(
            wifi: .init(channelNumber: 44, band: "5 GHz")
        )
        #expect(value("Channel", in: details.wifiRows) == "44 · 5 GHz")
    }

    @Test("Channel row omitted when all pieces are nil")
    func channelOmittedWhenEmpty() {
        let details = ConnectionDetails(wifi: .init(phyMode: "802.11ax"))
        #expect(value("Channel", in: details.wifiRows) == nil)
        #expect(value("PHY mode", in: details.wifiRows) == "802.11ax")
    }

    // MARK: - Mocks

    @Test("mockWifi is fully populated with a Wi-Fi group")
    func mockWifiPopulated() {
        let mock = ConnectionDetails.mockWifi
        #expect(mock.wifi != nil)
        #expect(!mock.interfaceRows.isEmpty)
        #expect(!mock.addressingRows.isEmpty)
        #expect(!mock.dnsDhcpRows.isEmpty)
        #expect(!mock.wifiRows.isEmpty)
    }

    @Test("mockEthernet has no Wi-Fi group and a 1000 Mbps link")
    func mockEthernetPopulated() {
        let mock = ConnectionDetails.mockEthernet
        #expect(mock.wifi == nil)
        #expect(mock.wifiRows.isEmpty)
        #expect(value("Link speed", in: mock.interfaceRows) == "1 Gbps")
    }

    @Test("mockVPN exposes only router, DNS, and hostname")
    func mockVPNPopulated() {
        let mock = ConnectionDetails.mockVPN
        #expect(mock.wifi == nil)
        #expect(value("Router", in: mock.addressingRows) != nil)
        #expect(value("Hostname", in: mock.addressingRows) != nil)
        #expect(!mock.dnsDhcpRows.isEmpty)
    }
}
