//
//  SystemConfigReader.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-04.
//

import Foundation
import SystemConfiguration
// DHCP lease helpers live in an explicit submodule not re-exported by the umbrella.
import SystemConfiguration.SCDynamicStoreCopyDHCPInfo

/// Active system proxies for the primary service; each "host:port" or nil.
struct ProxySnapshot: Equatable {
    var http: String?
    var https: String?
    var socks: String?
}

/// A read-only snapshot of `SCDynamicStore` network state for the primary service.
struct SystemConfigSnapshot: Equatable {
    var primaryInterface: String?
    var primaryInterfaceDisplayName: String?
    var primaryService: String?
    var routerAddress: String?
    var ipv6Router: String?
    var dnsServers: [String] = []
    var searchDomains: [String] = []
    var subnetMask: String?
    var ipv4ConfigMethod: String?
    var dhcpServer: String?
    var dhcpLeaseStart: Date?
    var dhcpLeaseExpiry: Date?
    var hostname: String?
    var computerName: String?
    var proxies = ProxySnapshot()
}

/// A seam over `SystemConfiguration` reads so the manager stays testable.
protocol SystemConfigReading {
    func snapshot() -> SystemConfigSnapshot
}

/// Reads router/DNS/subnet/DHCP/hostname facts from the live `SCDynamicStore`.
/// All reads are optional-safe: any key that is missing simply leaves its field nil.
struct SystemConfigReader: SystemConfigReading {

    /// Builds a snapshot from the current dynamic store. Sandbox-safe, no prompts.
    func snapshot() -> SystemConfigSnapshot {
        var result = SystemConfigSnapshot()

        guard let store = SCDynamicStoreCreate(nil, "QuickNetStats" as CFString, nil, nil) else {
            return result
        }

        // Global IPv4: router + primary interface/service identifiers.
        if let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            result.routerAddress = ipv4["Router"] as? String
            result.primaryInterface = ipv4["PrimaryInterface"] as? String
            result.primaryService = ipv4["PrimaryService"] as? String
        }

        // Global IPv6: router (present only when the primary service has IPv6 routing).
        if let ipv6 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any] {
            result.ipv6Router = ipv6["Router"] as? String
        }

        // Global DNS: resolvers + search domains.
        if let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any] {
            result.dnsServers = dns["ServerAddresses"] as? [String] ?? []
            result.searchDomains = dns["SearchDomains"] as? [String] ?? []
        }

        // Per-service IPv4: subnet mask, config method, and DHCP facts (if applicable).
        if let service = result.primaryService {
            let serviceKey = "State:/Network/Service/\(service)/IPv4" as CFString
            if let serviceIPv4 = SCDynamicStoreCopyValue(store, serviceKey) as? [String: Any] {
                result.subnetMask = (serviceIPv4["SubnetMasks"] as? [String])?.first
            }

            result.ipv4ConfigMethod = Self.ipv4ConfigMethod(store: store, service: service)

            if let dhcpInfo = SCDynamicStoreCopyDHCPInfo(store, service as CFString) {
                result.dhcpLeaseExpiry = DHCPInfoGetLeaseExpirationTime(dhcpInfo) as Date?
                result.dhcpLeaseStart = DHCPInfoGetLeaseStartTime(dhcpInfo) as Date?
                // DHCP option 54 = Server Identifier: the DHCP server's 4-byte IPv4.
                if let serverData = DHCPInfoGetOptionData(dhcpInfo, 54) as Data? {
                    result.dhcpServer = Self.ipv4String(from: serverData)
                }
            }
        }

        result.proxies = Self.proxies(store: store)

        // Local hostname (the ".local" Bonjour name, minus the suffix).
        result.hostname = SCDynamicStoreCopyLocalHostName(store) as String?

        // User-friendly computer name ("Federico's MacBook Pro").
        result.computerName = SCDynamicStoreCopyComputerName(store, nil) as String?

        // Human-readable display name for the primary interface, if resolvable.
        if let primary = result.primaryInterface {
            result.primaryInterfaceDisplayName = Self.displayName(forBSD: primary)
        }

        return result
    }

    /// The IPv4 `ConfigMethod` ("DHCP", "Manual", "LinkLocal"…) for the primary
    /// service. Prefers the persisted `Setup:` domain and falls back to the live
    /// `State:` domain, which is where a DHCP-assigned method actually appears.
    private static func ipv4ConfigMethod(store: SCDynamicStore, service: String) -> String? {
        for domain in ["Setup", "State"] {
            let key = "\(domain):/Network/Service/\(service)/IPv4" as CFString
            if let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
               let method = dict["ConfigMethod"] as? String {
                return method
            }
        }
        return nil
    }

    /// Reads the active HTTP/HTTPS/SOCKS proxies from `SCDynamicStoreCopyProxies`.
    /// Each proxy is included only when its `*Enable` flag is 1.
    private static func proxies(store: SCDynamicStore) -> ProxySnapshot {
        guard let dict = SCDynamicStoreCopyProxies(store) as? [String: Any] else {
            return ProxySnapshot()
        }
        return ProxySnapshot(
            http: endpoint(in: dict, enable: kSCPropNetProxiesHTTPEnable,
                           host: kSCPropNetProxiesHTTPProxy, port: kSCPropNetProxiesHTTPPort),
            https: endpoint(in: dict, enable: kSCPropNetProxiesHTTPSEnable,
                            host: kSCPropNetProxiesHTTPSProxy, port: kSCPropNetProxiesHTTPSPort),
            socks: endpoint(in: dict, enable: kSCPropNetProxiesSOCKSEnable,
                            host: kSCPropNetProxiesSOCKSProxy, port: kSCPropNetProxiesSOCKSPort)
        )
    }

    /// Formats one proxy as "host:port" (or just "host" when no port is set) when
    /// its enable flag is 1; nil when disabled or the host is missing/empty.
    private static func endpoint(
        in dict: [String: Any],
        enable: CFString,
        host: CFString,
        port: CFString
    ) -> String? {
        guard (dict[enable as String] as? Int) == 1,
              let hostValue = dict[host as String] as? String, !hostValue.isEmpty else {
            return nil
        }
        if let portValue = dict[port as String] as? Int {
            return "\(hostValue):\(portValue)"
        }
        return hostValue
    }

    /// Formats a 4-byte IPv4 address blob (e.g. DHCP option 54) as a dotted quad.
    private static func ipv4String(from data: Data) -> String? {
        guard data.count == 4 else { return nil }
        return data.map { String($0) }.joined(separator: ".")
    }

    /// Maps a BSD interface name (e.g. "en0") to its localized display name ("Wi-Fi").
    private static func displayName(forBSD bsdName: String) -> String? {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for interface in interfaces where SCNetworkInterfaceGetBSDName(interface) as String? == bsdName {
            return SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
        }
        return nil
    }
}
