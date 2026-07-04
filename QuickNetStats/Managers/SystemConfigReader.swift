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

/// A read-only snapshot of `SCDynamicStore` network state for the primary service.
struct SystemConfigSnapshot: Equatable {
    var primaryInterface: String?
    var primaryInterfaceDisplayName: String?
    var primaryService: String?
    var routerAddress: String?
    var dnsServers: [String] = []
    var searchDomains: [String] = []
    var subnetMask: String?
    var dhcpLeaseExpiry: Date?
    var hostname: String?
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

        // Global DNS: resolvers + search domains.
        if let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any] {
            result.dnsServers = dns["ServerAddresses"] as? [String] ?? []
            result.searchDomains = dns["SearchDomains"] as? [String] ?? []
        }

        // Per-service IPv4: subnet mask, and DHCP lease expiry (if the service uses DHCP).
        if let service = result.primaryService {
            let serviceKey = "State:/Network/Service/\(service)/IPv4" as CFString
            if let serviceIPv4 = SCDynamicStoreCopyValue(store, serviceKey) as? [String: Any] {
                result.subnetMask = (serviceIPv4["SubnetMasks"] as? [String])?.first
            }

            if let dhcpInfo = SCDynamicStoreCopyDHCPInfo(store, service as CFString) {
                result.dhcpLeaseExpiry = DHCPInfoGetLeaseExpirationTime(dhcpInfo) as Date?
            }
        }

        // Local hostname (the ".local" Bonjour name, minus the suffix).
        result.hostname = SCDynamicStoreCopyLocalHostName(store) as String?

        // Human-readable display name for the primary interface, if resolvable.
        if let primary = result.primaryInterface {
            result.primaryInterfaceDisplayName = Self.displayName(forBSD: primary)
        }

        return result
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
