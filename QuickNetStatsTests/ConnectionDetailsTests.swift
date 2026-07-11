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

    // MARK: - Link speed units

    @Test("Link speed row defaults to bits (native Mbps/Gbps)")
    func linkSpeedDefaultsToBits() {
        let details = ConnectionDetails(interface: .init(linkSpeedMbps: 210))
        #expect(value("Link speed", in: details.interfaceRows(rateUnit: .bitsPerSecond)) == "210 Mbps")
    }

    @Test("Link speed row converts to bytes when requested")
    func linkSpeedInBytes() {
        let details = ConnectionDetails(interface: .init(linkSpeedMbps: 210))
        #expect(value("Link speed", in: details.interfaceRows(rateUnit: .bytesPerSecond)) == "26.25 MB/s")
    }

    @Test("Media, Supports, and Also available rows follow Link speed in order")
    func interfaceExtraRowsOrder() {
        let details = ConnectionDetails(
            interface: .init(
                bsdName: "en5",
                displayName: "Ethernet",
                macAddress: "aa:bb:cc:dd:ee:ff",
                mtu: 1500,
                linkSpeedMbps: 1000,
                mediaDescription: "1000baseT full-duplex",
                supports: "IPv4 · IPv6 · DNS",
                otherInterfaces: ["Wi-Fi (en0)", "Cellular (pdp_ip0)"]
            )
        )
        #expect(details.interfaceRows.map(\.label) == [
            "Name", "MAC address", "MTU", "Link speed", "Media", "Supports", "Also available"
        ])
        #expect(value("Media", in: details.interfaceRows) == "1000baseT full-duplex")
        #expect(value("Supports", in: details.interfaceRows) == "IPv4 · IPv6 · DNS")
        #expect(value("Also available", in: details.interfaceRows) == "Wi-Fi (en0), Cellular (pdp_ip0)")
    }

    @Test("Media, Supports, and Also available rows are omitted when unset")
    func interfaceExtraRowsOmitted() {
        let details = ConnectionDetails(interface: .init(bsdName: "en0"))
        #expect(value("Media", in: details.interfaceRows) == nil)
        #expect(value("Supports", in: details.interfaceRows) == nil)
        #expect(value("Also available", in: details.interfaceRows) == nil)
    }

    // MARK: - Interface BSSID

    @Test("interfaceRows includes BSSID after MAC address when opted in")
    func interfaceRowsIncludeBSSIDWhenOptedIn() {
        let rows = ConnectionDetails.mockWifi.interfaceRows(includeBSSID: true)
        let labels = rows.map(\.label)
        #expect(rows.contains(DetailRow(label: "BSSID", value: "aa:bb:cc:11:22:33")))
        #expect(labels.firstIndex(of: "BSSID") == labels.firstIndex(of: "MAC address").map { $0 + 1 })
    }

    @Test("interfaceRows omits BSSID by default")
    func interfaceRowsOmitBSSIDByDefault() {
        let labels = ConnectionDetails.mockWifi.interfaceRows().map(\.label)
        #expect(!labels.contains("BSSID"))
    }

    @Test("interfaceRows omits BSSID when the value is missing")
    func interfaceRowsOmitNilBSSID() {
        var details = ConnectionDetails.mockWifi
        details.interface.bssid = nil
        let labels = details.interfaceRows(includeBSSID: true).map(\.label)
        #expect(!labels.contains("BSSID"))
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

    @Test("All addressing rows appear in design order when populated")
    func addressingFullOrder() {
        let details = ConnectionDetails(
            addressing: .init(
                ipv6Address: "2a00::1",
                publicIPv6: "2a01::2",
                subnetMask: "255.255.255.0",
                routerAddress: "192.168.1.1",
                hostname: "mac",
                ipv6Router: "fe80::1",
                broadcastAddress: "192.168.1.255",
                ipv4ConfigMethod: "DHCP",
                computerName: "Federico's Mac"
            )
        )
        #expect(details.addressingRows.map(\.label) == [
            "Router", "Router (IPv6)", "Subnet mask", "Broadcast",
            "IPv6 (local)", "Public IPv6", "IPv4 config", "Hostname", "Computer name"
        ])
        #expect(value("Router (IPv6)", in: details.addressingRows) == "fe80::1")
        #expect(value("Broadcast", in: details.addressingRows) == "192.168.1.255")
        #expect(value("IPv4 config", in: details.addressingRows) == "DHCP")
        #expect(value("Computer name", in: details.addressingRows) == "Federico's Mac")
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

    @Test("DHCP server and Lease started rows precede Lease expires in order")
    func dnsDhcpFullOrder() {
        let details = ConnectionDetails(
            dnsDhcp: .init(
                dnsServers: ["1.1.1.1"],
                searchDomains: ["home"],
                dhcpServer: "192.168.1.1",
                dhcpLeaseStart: Date(),
                dhcpLeaseExpiry: Date().addingTimeInterval(86_400)
            )
        )
        #expect(details.dnsDhcpRows.map(\.label) == [
            "DNS servers", "Search domains", "DHCP server", "Lease started", "DHCP lease expires"
        ])
        #expect(value("DHCP server", in: details.dnsDhcpRows) == "192.168.1.1")
        #expect(value("Lease started", in: details.dnsDhcpRows) != nil)
    }

    @Test("DHCP server and Lease started rows are omitted when unset")
    func dnsDhcpExtraRowsOmitted() {
        let details = ConnectionDetails(dnsDhcp: .init(dnsServers: ["1.1.1.1"]))
        #expect(value("DHCP server", in: details.dnsDhcpRows) == nil)
        #expect(value("Lease started", in: details.dnsDhcpRows) == nil)
    }

    // MARK: - Proxy group

    @Test("A fully populated proxy yields three rows in HTTP/HTTPS/SOCKS order")
    func proxyFullRows() {
        let details = ConnectionDetails(
            proxy: .init(httpProxy: "p.local:80", httpsProxy: "p.local:443", socksProxy: "s.local:1080")
        )
        #expect(details.proxyRows.map(\.label) == ["HTTP", "HTTPS", "SOCKS"])
        #expect(value("HTTP", in: details.proxyRows) == "p.local:80")
        #expect(value("HTTPS", in: details.proxyRows) == "p.local:443")
        #expect(value("SOCKS", in: details.proxyRows) == "s.local:1080")
    }

    @Test("A partially populated proxy omits the nil entries")
    func proxyPartialRows() {
        let details = ConnectionDetails(proxy: .init(httpsProxy: "p.local:443"))
        #expect(details.proxyRows.map(\.label) == ["HTTPS"])
    }

    @Test("An all-nil proxy produces no rows so the group never renders")
    func proxyEmptyRows() {
        let details = ConnectionDetails()
        #expect(details.proxyRows.isEmpty)
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

    // MARK: - Wi-Fi generation

    @Test("PHY mode maps to its Wi-Fi generation", arguments: [
        ("802.11b", "Wi-Fi 1"),
        ("802.11a", "Wi-Fi 2"),
        ("802.11g", "Wi-Fi 3"),
        ("802.11n", "Wi-Fi 4"),
        ("802.11ac", "Wi-Fi 5"),
        ("802.11be", "Wi-Fi 7")
    ])
    func phyModeMapsToGeneration(phy: String, expected: String) {
        #expect(ConnectionDetails.Wifi(phyMode: phy).generation == expected)
    }

    @Test("802.11ax on 6 GHz is Wi-Fi 6E")
    func axSixGigIsSixE() {
        let wifi = ConnectionDetails.Wifi(band: "6 GHz", phyMode: "802.11ax")
        #expect(wifi.generation == "Wi-Fi 6E")
    }

    @Test("802.11ax below 6 GHz is Wi-Fi 6", arguments: [Optional("5 GHz"), nil])
    func axBelowSixGigIsSix(band: String?) {
        let wifi = ConnectionDetails.Wifi(band: band, phyMode: "802.11ax")
        #expect(wifi.generation == "Wi-Fi 6")
    }

    @Test("nil PHY mode yields no generation and omits the row")
    func nilPhyModeNoGeneration() {
        let details = ConnectionDetails(wifi: .init(channelNumber: 44, band: "5 GHz"))
        #expect(details.wifi?.generation == nil)
        #expect(value("Generation", in: details.wifiRows) == nil)
    }

    @Test("Generation row follows PHY mode in a fully populated Wi-Fi group")
    func generationRowPosition() {
        let mock = ConnectionDetails.mockWifi
        #expect(mock.wifiRows.map(\.label) == [
            "Channel", "PHY mode", "Generation", "Mode", "Tx power", "Security", "Country code"
        ])
        #expect(value("Generation", in: mock.wifiRows) == "Wi-Fi 6")
    }

    @Test("Mode and Tx power rows follow Generation and omit when unset")
    func wifiModeAndTxPowerRows() {
        let populated = ConnectionDetails(wifi: .init(phyMode: "802.11ax", mode: "Station", txPowerMw: 100))
        #expect(value("Mode", in: populated.wifiRows) == "Station")
        #expect(value("Tx power", in: populated.wifiRows) == "100 mW")
        #expect(populated.wifiRows.map(\.label) == ["PHY mode", "Generation", "Mode", "Tx power"])

        let bare = ConnectionDetails(wifi: .init(phyMode: "802.11ax"))
        #expect(value("Mode", in: bare.wifiRows) == nil)
        #expect(value("Tx power", in: bare.wifiRows) == nil)
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

    @Test("mockWifi exercises the new fields and proxy group")
    func mockWifiHasNewFields() {
        let mock = ConnectionDetails.mockWifi
        #expect(mock.interface.supports != nil)
        #expect(!mock.interface.otherInterfaces.isEmpty)
        #expect(mock.addressing.ipv6Router != nil)
        #expect(mock.addressing.computerName != nil)
        #expect(mock.dnsDhcp.dhcpServer != nil)
        #expect(mock.dnsDhcp.dhcpLeaseStart != nil)
        #expect(!mock.proxyRows.isEmpty)
        #expect(mock.wifi?.mode != nil)
        #expect(mock.wifi?.txPowerMw != nil)
    }

    @Test("mockEthernet reports a media description and no proxy group")
    func mockEthernetHasMedia() {
        let mock = ConnectionDetails.mockEthernet
        #expect(mock.interface.mediaDescription != nil)
        #expect(mock.proxyRows.isEmpty)
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

    @Test("mockVPN leaves the new fields nil to exercise omission")
    func mockVPNOmitsNewFields() {
        let mock = ConnectionDetails.mockVPN
        #expect(mock.interface.mediaDescription == nil)
        #expect(mock.interface.supports == nil)
        #expect(mock.interface.otherInterfaces.isEmpty)
        #expect(mock.addressing.ipv6Router == nil)
        #expect(mock.addressing.broadcastAddress == nil)
        #expect(mock.addressing.ipv4ConfigMethod == nil)
        #expect(mock.addressing.computerName == nil)
        #expect(mock.proxyRows.isEmpty)
    }
}
