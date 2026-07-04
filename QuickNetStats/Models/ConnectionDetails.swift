//
//  ConnectionDetails.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-04.
//

import Foundation

/// A single label–value pair rendered as one row in a details group.
/// `id` is the label so a group cannot contain duplicate labels.
struct DetailRow: Identifiable, Equatable {
    let label: String
    let value: String
    var id: String { label }
}

/// One immutable snapshot of advanced network information, grouped to mirror the
/// dropdown UI. Every leaf field is optional: a `nil` field means "could not be
/// determined" and its row is simply omitted from the group's row array.
struct ConnectionDetails: Equatable {

    // MARK: - Groups

    /// Physical/link-layer facts about the primary interface.
    struct Interface: Equatable {
        var bsdName: String?
        var displayName: String?
        var macAddress: String?
        var mtu: Int?
        var linkSpeedMbps: Double?
    }

    /// Layer-3 addressing for the primary interface.
    struct Addressing: Equatable {
        var ipv6Address: String?
        var publicIPv6: String?
        var subnetMask: String?
        var routerAddress: String?
        var hostname: String?
    }

    /// Name resolution and DHCP lease information.
    struct DnsDhcp: Equatable {
        var dnsServers: [String] = []
        var searchDomains: [String] = []
        var dhcpLeaseExpiry: Date?
    }

    /// Wi-Fi RF/PHY facts; the whole group is `nil` on non-Wi-Fi interfaces.
    struct Wifi: Equatable {
        var channelNumber: Int?
        var band: String?          // "2.4 GHz" | "5 GHz" | "6 GHz"
        var channelWidthMHz: Int?
        var phyMode: String?       // "802.11ax"
        var security: String?      // "WPA3 Personal"
        var countryCode: String?
    }

    // MARK: - Properties

    var interface = Interface()
    var addressing = Addressing()
    var dnsDhcp = DnsDhcp()
    var wifi: Wifi?

    // MARK: - Computed Rows

    /// Interface group rows in design order; nil fields are omitted.
    var interfaceRows: [DetailRow] {
        var rows: [DetailRow] = []
        if let name = Self.interfaceName(interface) {
            rows.append(DetailRow(label: "Name", value: name))
        }
        if let mac = interface.macAddress {
            rows.append(DetailRow(label: "MAC address", value: mac))
        }
        if let mtu = interface.mtu {
            rows.append(DetailRow(label: "MTU", value: "\(mtu)"))
        }
        if let speed = interface.linkSpeedMbps {
            rows.append(DetailRow(label: "Link speed", value: Self.linkSpeedText(speed)))
        }
        return rows
    }

    /// Addressing group rows in design order; nil fields are omitted.
    var addressingRows: [DetailRow] {
        var rows: [DetailRow] = []
        if let router = addressing.routerAddress {
            rows.append(DetailRow(label: "Router", value: router))
        }
        if let subnet = addressing.subnetMask {
            rows.append(DetailRow(label: "Subnet mask", value: subnet))
        }
        if let ipv6 = addressing.ipv6Address {
            rows.append(DetailRow(label: "IPv6 (local)", value: ipv6))
        }
        if let publicIPv6 = addressing.publicIPv6 {
            rows.append(DetailRow(label: "Public IPv6", value: publicIPv6))
        }
        if let hostname = addressing.hostname {
            rows.append(DetailRow(label: "Hostname", value: hostname))
        }
        return rows
    }

    /// DNS & DHCP group rows in design order; empty arrays / nil dates are omitted.
    var dnsDhcpRows: [DetailRow] {
        var rows: [DetailRow] = []
        if !dnsDhcp.dnsServers.isEmpty {
            rows.append(DetailRow(label: "DNS servers", value: dnsDhcp.dnsServers.joined(separator: ", ")))
        }
        if !dnsDhcp.searchDomains.isEmpty {
            rows.append(DetailRow(label: "Search domains", value: dnsDhcp.searchDomains.joined(separator: ", ")))
        }
        if let lease = dnsDhcp.dhcpLeaseExpiry {
            rows.append(DetailRow(
                label: "DHCP lease expires",
                value: lease.formatted(date: .abbreviated, time: .shortened)
            ))
        }
        return rows
    }

    /// Wi-Fi group rows in design order; `[]` when `wifi == nil`.
    var wifiRows: [DetailRow] {
        guard let wifi else { return [] }
        var rows: [DetailRow] = []
        if let channel = Self.channelText(wifi) {
            rows.append(DetailRow(label: "Channel", value: channel))
        }
        if let phy = wifi.phyMode {
            rows.append(DetailRow(label: "PHY mode", value: phy))
        }
        if let security = wifi.security {
            rows.append(DetailRow(label: "Security", value: security))
        }
        if let country = wifi.countryCode {
            rows.append(DetailRow(label: "Country code", value: country))
        }
        return rows
    }

    // MARK: - Formatters

    /// Composes the interface name as "displayName (bsdName)", falling back to
    /// whichever single value is present, or `nil` when both are missing.
    private static func interfaceName(_ interface: Interface) -> String? {
        switch (interface.displayName, interface.bsdName) {
        case let (display?, bsd?): return "\(display) (\(bsd))"
        case let (display?, nil): return display
        case let (nil, bsd?): return bsd
        default: return nil
        }
    }

    /// Formats a link speed in Mbps: whole Mbps below 1000, otherwise Gbps with
    /// any trailing `.0` stripped ("866 Mbps", "1 Gbps", "2.5 Gbps").
    /// Internal so `LiveConnectionStats` can reuse it for the Tx-rate row.
    static func linkSpeedText(_ mbps: Double) -> String {
        if mbps < 1000 {
            return "\(Int(mbps.rounded())) Mbps"
        }
        let gbps = mbps / 1000
        if gbps.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(gbps)) Gbps"
        }
        return "\(gbps) Gbps"
    }

    /// Composes "44 · 5 GHz · 80 MHz", dropping nil pieces; `nil` when all are nil.
    private static func channelText(_ wifi: Wifi) -> String? {
        var parts: [String] = []
        if let number = wifi.channelNumber { parts.append("\(number)") }
        if let band = wifi.band { parts.append(band) }
        if let width = wifi.channelWidthMHz { parts.append("\(width) MHz") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Mockups

    /// Fully populated Wi-Fi snapshot for previews and tests.
    static let mockWifi = ConnectionDetails(
        interface: .init(
            bsdName: "en0",
            displayName: "Wi-Fi",
            macAddress: "a4:83:e7:1a:2b:3c",
            mtu: 1500,
            linkSpeedMbps: 866
        ),
        addressing: .init(
            ipv6Address: "2a00:1450:4009:82b::200e",
            publicIPv6: "2a01:e11:1234:5678::1",
            subnetMask: "255.255.255.0",
            routerAddress: "192.168.1.1",
            hostname: "Federicos-MacBook-Pro"
        ),
        dnsDhcp: .init(
            dnsServers: ["192.168.1.1", "1.1.1.1"],
            searchDomains: ["home"],
            dhcpLeaseExpiry: Date().addingTimeInterval(86_400)
        ),
        wifi: .init(
            channelNumber: 44,
            band: "5 GHz",
            channelWidthMHz: 80,
            phyMode: "802.11ax",
            security: "WPA3 Personal",
            countryCode: "IT"
        )
    )

    /// Wired snapshot: no Wi-Fi group, 1 Gbps link.
    static let mockEthernet = ConnectionDetails(
        interface: .init(
            bsdName: "en5",
            displayName: "Ethernet",
            macAddress: "a4:83:e7:44:55:66",
            mtu: 1500,
            linkSpeedMbps: 1000
        ),
        addressing: .init(
            ipv6Address: "2a00:1450:4009:82b::abcd",
            subnetMask: "255.255.255.0",
            routerAddress: "192.168.1.1",
            hostname: "Federicos-MacBook-Pro"
        ),
        dnsDhcp: .init(
            dnsServers: ["192.168.1.1"],
            searchDomains: ["home"],
            dhcpLeaseExpiry: Date().addingTimeInterval(86_400)
        ),
        wifi: nil
    )

    /// VPN snapshot: only router, DNS, and hostname are determinable.
    static let mockVPN = ConnectionDetails(
        interface: .init(bsdName: "utun3", displayName: "VPN"),
        addressing: .init(routerAddress: "10.8.0.1", hostname: "Federicos-MacBook-Pro"),
        dnsDhcp: .init(dnsServers: ["10.8.0.1"]),
        wifi: nil
    )
}
