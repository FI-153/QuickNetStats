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
        /// Active media type for wired links ("1000baseT full-duplex"); nil off Ethernet.
        var mediaDescription: String?
        /// Pre-formatted NWPath capability list ("IPv4 · IPv6 · DNS"); nil when unknown.
        var supports: String?
        /// Other usable interfaces beside the primary, e.g. `["Ethernet (en1)"]`.
        var otherInterfaces: [String] = []
    }

    /// Layer-3 addressing for the primary interface.
    struct Addressing: Equatable {
        var ipv6Address: String?
        var publicIPv6: String?
        var subnetMask: String?
        var routerAddress: String?
        var hostname: String?
        var ipv6Router: String?
        var broadcastAddress: String?
        /// IPv4 configuration method ("DHCP", "Manual", "LinkLocal"…).
        var ipv4ConfigMethod: String?
        var computerName: String?
    }

    /// Name resolution and DHCP lease information.
    struct DnsDhcp: Equatable {
        var dnsServers: [String] = []
        var searchDomains: [String] = []
        var dhcpServer: String?
        var dhcpLeaseStart: Date?
        var dhcpLeaseExpiry: Date?
    }

    /// Active system proxies for the primary service; each is "host:port" or nil
    /// when that proxy type is disabled. The whole group's rows vanish when all nil.
    struct Proxy: Equatable {
        var httpProxy: String?
        var httpsProxy: String?
        var socksProxy: String?
    }

    /// Wi-Fi RF/PHY facts; the whole group is `nil` on non-Wi-Fi interfaces.
    struct Wifi: Equatable {
        var channelNumber: Int?
        var band: String?          // "2.4 GHz" | "5 GHz" | "6 GHz"
        var channelWidthMHz: Int?
        var phyMode: String?       // "802.11ax"
        var mode: String?          // "Station" | "IBSS" | "Host AP"
        var txPowerMw: Int?
        var security: String?      // "WPA3 Personal"
        var countryCode: String?

        /// Marketing Wi-Fi generation ("Wi-Fi 6", "Wi-Fi 6E", …) derived from the
        /// PHY mode and band, both of which come from `WifiReader`'s closed value
        /// set. `nil` when the PHY mode is unknown/unset, so its row is omitted.
        var generation: String? {
            switch phyMode {
            case "802.11b": return "Wi-Fi 1"
            case "802.11a": return "Wi-Fi 2"
            case "802.11g": return "Wi-Fi 3"
            case "802.11n": return "Wi-Fi 4"
            case "802.11ac": return "Wi-Fi 5"
            case "802.11ax": return band == "6 GHz" ? "Wi-Fi 6E" : "Wi-Fi 6"
            case "802.11be": return "Wi-Fi 7"
            default: return nil
            }
        }
    }

    // MARK: - Properties

    var interface = Interface()
    var addressing = Addressing()
    var dnsDhcp = DnsDhcp()
    var proxy = Proxy()
    var wifi: Wifi?

    // MARK: - Computed Rows

    /// Interface group rows in design order; nil fields are omitted.
    /// Convenience alias for `interfaceRows(rateUnit:)` in the native (bits) unit.
    var interfaceRows: [DetailRow] { interfaceRows(rateUnit: .bitsPerSecond) }

    /// Interface group rows in design order; nil fields are omitted. `rateUnit`
    /// governs only the "Link speed" row's unit family; it defaults to the native
    /// bits unit so existing call sites and previews stay unchanged.
    func interfaceRows(rateUnit: RateUnit = .bitsPerSecond) -> [DetailRow] {
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
            rows.append(DetailRow(label: "Link speed", value: Self.linkSpeedText(speed, in: rateUnit)))
        }
        if let media = interface.mediaDescription {
            rows.append(DetailRow(label: "Media", value: media))
        }
        if let supports = interface.supports {
            rows.append(DetailRow(label: "Supports", value: supports))
        }
        if !interface.otherInterfaces.isEmpty {
            rows.append(DetailRow(label: "Also available", value: interface.otherInterfaces.joined(separator: ", ")))
        }
        return rows
    }

    /// Addressing group rows in design order; nil fields are omitted.
    var addressingRows: [DetailRow] {
        var rows: [DetailRow] = []
        if let router = addressing.routerAddress {
            rows.append(DetailRow(label: "Router", value: router))
        }
        if let ipv6Router = addressing.ipv6Router {
            rows.append(DetailRow(label: "Router (IPv6)", value: ipv6Router))
        }
        if let subnet = addressing.subnetMask {
            rows.append(DetailRow(label: "Subnet mask", value: subnet))
        }
        if let broadcast = addressing.broadcastAddress {
            rows.append(DetailRow(label: "Broadcast", value: broadcast))
        }
        if let ipv6 = addressing.ipv6Address {
            rows.append(DetailRow(label: "IPv6 (local)", value: ipv6))
        }
        if let publicIPv6 = addressing.publicIPv6 {
            rows.append(DetailRow(label: "Public IPv6", value: publicIPv6))
        }
        if let configMethod = addressing.ipv4ConfigMethod {
            rows.append(DetailRow(label: "IPv4 config", value: configMethod))
        }
        if let hostname = addressing.hostname {
            rows.append(DetailRow(label: "Hostname", value: hostname))
        }
        if let computerName = addressing.computerName {
            rows.append(DetailRow(label: "Computer name", value: computerName))
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
        if let server = dnsDhcp.dhcpServer {
            rows.append(DetailRow(label: "DHCP server", value: server))
        }
        if let start = dnsDhcp.dhcpLeaseStart {
            rows.append(DetailRow(
                label: "Lease started",
                value: start.formatted(date: .abbreviated, time: .shortened)
            ))
        }
        if let lease = dnsDhcp.dhcpLeaseExpiry {
            rows.append(DetailRow(
                label: "DHCP lease expires",
                value: lease.formatted(date: .abbreviated, time: .shortened)
            ))
        }
        return rows
    }

    /// Proxy group rows in HTTP/HTTPS/SOCKS order; nil proxies are omitted, so an
    /// all-nil `Proxy` yields `[]` and the group never renders (existing convention).
    var proxyRows: [DetailRow] {
        var rows: [DetailRow] = []
        if let http = proxy.httpProxy {
            rows.append(DetailRow(label: "HTTP", value: http))
        }
        if let https = proxy.httpsProxy {
            rows.append(DetailRow(label: "HTTPS", value: https))
        }
        if let socks = proxy.socksProxy {
            rows.append(DetailRow(label: "SOCKS", value: socks))
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
        if let generation = wifi.generation {
            rows.append(DetailRow(label: "Generation", value: generation))
        }
        if let mode = wifi.mode {
            rows.append(DetailRow(label: "Mode", value: mode))
        }
        if let txPower = wifi.txPowerMw {
            rows.append(DetailRow(label: "Tx power", value: "\(txPower) mW"))
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

    /// Formats a link speed in Mbps in its native bits unit: whole Mbps below 1000,
    /// otherwise Gbps with any trailing `.0` stripped ("866 Mbps", "1 Gbps",
    /// "2.5 Gbps"). Internal so `LiveConnectionStats` can reuse it for the Tx-rate row.
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

    /// Formats a link speed in Mbps, displayed in `unit`. The native bits unit keeps
    /// the historical `linkSpeedText(_:)` output byte-for-byte; the bytes unit routes
    /// through `DataRate` after converting the Mbps value to bits per second.
    static func linkSpeedText(_ mbps: Double, in unit: RateUnit) -> String {
        switch unit {
        case .bitsPerSecond:
            return linkSpeedText(mbps)
        case .bytesPerSecond:
            return DataRate.text(bitsPerSecond: mbps * 1_000_000, in: .bytesPerSecond)
        }
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
            linkSpeedMbps: 866,
            supports: "IPv4 · IPv6 · DNS",
            otherInterfaces: ["Ethernet (en5)"]
        ),
        addressing: .init(
            ipv6Address: "2a00:1450:4009:82b::200e",
            publicIPv6: "2a01:e11:1234:5678::1",
            subnetMask: "255.255.255.0",
            routerAddress: "192.168.1.1",
            hostname: "Federicos-MacBook-Pro",
            ipv6Router: "fe80::1",
            broadcastAddress: "192.168.1.255",
            ipv4ConfigMethod: "DHCP",
            computerName: "Federico's MacBook Pro"
        ),
        dnsDhcp: .init(
            dnsServers: ["192.168.1.1", "1.1.1.1"],
            searchDomains: ["home"],
            dhcpServer: "192.168.1.1",
            dhcpLeaseStart: Date().addingTimeInterval(-3_600),
            dhcpLeaseExpiry: Date().addingTimeInterval(86_400)
        ),
        proxy: .init(httpProxy: "proxy.local:8080", httpsProxy: "proxy.local:8080"),
        wifi: .init(
            channelNumber: 44,
            band: "5 GHz",
            channelWidthMHz: 80,
            phyMode: "802.11ax",
            mode: "Station",
            txPowerMw: 100,
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
            linkSpeedMbps: 1000,
            mediaDescription: "1000baseT full-duplex",
            supports: "IPv4 · IPv6 · DNS",
            otherInterfaces: ["Wi-Fi (en0)"]
        ),
        addressing: .init(
            ipv6Address: "2a00:1450:4009:82b::abcd",
            subnetMask: "255.255.255.0",
            routerAddress: "192.168.1.1",
            hostname: "Federicos-MacBook-Pro",
            ipv6Router: "fe80::abcd",
            broadcastAddress: "192.168.1.255",
            ipv4ConfigMethod: "Manual",
            computerName: "Federico's MacBook Pro"
        ),
        dnsDhcp: .init(
            dnsServers: ["192.168.1.1"],
            searchDomains: ["home"],
            dhcpServer: "192.168.1.1",
            dhcpLeaseStart: Date().addingTimeInterval(-3_600),
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
