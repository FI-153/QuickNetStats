//
//  InterfaceReader.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-04.
//

import Foundation

/// A read-only snapshot of BSD-layer facts for a single interface.
struct InterfaceSnapshot: Equatable {
    var macAddress: String?      // "aa:bb:cc:dd:ee:ff"
    var mtu: Int?
    var ipv6Address: String?
    var linkSpeedMbps: Double?
    var rxBytes: UInt64?
    var txBytes: UInt64?
}

/// A seam over `getifaddrs`/`sysctl` reads so the manager stays testable.
protocol InterfaceReading {
    func snapshot(for bsdName: String) -> InterfaceSnapshot
}

/// Reads MAC, MTU, local IPv6, link speed, and 64-bit byte counters for a BSD
/// interface via `getifaddrs` (link + IPv6 facts) and `sysctl NET_RT_IFLIST2`
/// (rollover-safe counters). All reads are optional-safe.
struct InterfaceReader: InterfaceReading {

    /// Builds a snapshot for the given BSD interface name (e.g. "en0").
    func snapshot(for bsdName: String) -> InterfaceSnapshot {
        var result = InterfaceSnapshot()
        var ipv6Candidates: [String] = []

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            defer { freeifaddrs(ifaddr) }

            for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
                let interface = ptr.pointee
                guard String(cString: interface.ifa_name) == bsdName,
                      let addr = interface.ifa_addr else { continue }

                switch Int32(addr.pointee.sa_family) {
                case AF_LINK:
                    Self.readLinkLayer(addr: addr, data: interface.ifa_data, into: &result)
                case AF_INET6:
                    if let ipv6 = Self.ipv6String(from: addr) {
                        ipv6Candidates.append(ipv6)
                    }
                default:
                    break
                }
            }
        }

        result.ipv6Address = Self.preferredIPv6(from: ipv6Candidates)
        (result.rxBytes, result.txBytes) = Self.byteCounters(for: bsdName)
        return result
    }

    // MARK: - IPv6 preference

    /// Picks the best local IPv6: global unicast first, then ULA (`fc00::/7`),
    /// never link-local (`fe80::/10`). Case-insensitive; deterministic first match.
    static func preferredIPv6(from candidates: [String]) -> String? {
        // Drop link-local; only fe80:: is ever assigned in practice.
        // ponytail: fe80 prefix check; widen to the full fe80::/10 range only if a
        // real fe9x/fexx link-local address ever surfaces.
        let routable = candidates.filter { !$0.lowercased().hasPrefix("fe80") }
        if let global = routable.first(where: {
            let lower = $0.lowercased()
            return !lower.hasPrefix("fc") && !lower.hasPrefix("fd")
        }) {
            return global
        }
        return routable.first
    }

    // MARK: - getifaddrs decoding

    /// Decodes MAC address, MTU, and link speed from an `AF_LINK` entry.
    private static func readLinkLayer(
        addr: UnsafeMutablePointer<sockaddr>,
        data: UnsafeMutableRawPointer?,
        into result: inout InterfaceSnapshot
    ) {
        addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dlPtr in
            let dl = dlPtr.pointee
            guard dl.sdl_alen == 6,
                  let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data),
                  // The MAC bytes must lie inside the sdl_len-sized allocation.
                  dataOffset + Int(dl.sdl_nlen) + 6 <= Int(dl.sdl_len) else { return }
            // LLADDR(sdl) = sdl_data + sdl_nlen; read from the raw allocation so we
            // don't rely on the 12-byte declared size of the sdl_data tuple.
            let macStart = UnsafeRawPointer(dlPtr)
                .advanced(by: dataOffset + Int(dl.sdl_nlen))
                .assumingMemoryBound(to: UInt8.self)
            result.macAddress = (0..<6)
                .map { String(format: "%02x", macStart[$0]) }
                .joined(separator: ":")
        }

        if let data {
            data.withMemoryRebound(to: if_data.self, capacity: 1) { dataPtr in
                result.mtu = Int(dataPtr.pointee.ifi_mtu)
                let baudrate = dataPtr.pointee.ifi_baudrate
                if baudrate > 0 {
                    result.linkSpeedMbps = Double(baudrate) / 1_000_000
                }
            }
        }
    }

    /// Formats an `AF_INET6` address as a numeric string, stripping any `%scope`.
    private static func ipv6String(from addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            addr, socklen_t(addr.pointee.sa_len),
            &host, socklen_t(host.count),
            nil, 0, NI_NUMERICHOST
        )
        guard status == 0 else { return nil }
        var address = String(cString: host)
        if let scope = address.firstIndex(of: "%") {
            address = String(address[..<scope])
        }
        return address
    }

    // MARK: - Byte counters

    /// Reads 64-bit rx/tx byte counters via `sysctl NET_RT_IFLIST2` (avoids the
    /// 32-bit rollover of the `getifaddrs` counters). Returns `(nil, nil)` if the
    /// interface is unknown or the query fails.
    private static func byteCounters(for bsdName: String) -> (UInt64?, UInt64?) {
        let index = if_nametoindex(bsdName)
        guard index != 0 else { return (nil, nil) }

        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return (nil, nil)
        }

        var buffer = [UInt8](repeating: 0, count: length)
        let success = buffer.withUnsafeMutableBytes { raw in
            sysctl(&mib, u_int(mib.count), raw.baseAddress, &length, nil, 0) == 0
        }
        guard success else { return (nil, nil) }

        return buffer.withUnsafeBytes { raw -> (UInt64?, UInt64?) in
            guard let base = raw.baseAddress else { return (nil, nil) }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = base.advanced(by: offset).loadUnaligned(as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }

                if header.ifm_type == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length,
                   messageLength >= MemoryLayout<if_msghdr2>.size {
                    let header2 = base.advanced(by: offset).loadUnaligned(as: if_msghdr2.self)
                    if UInt32(header2.ifm_index) == index {
                        return (header2.ifm_data.ifi_ibytes, header2.ifm_data.ifi_obytes)
                    }
                }
                offset += messageLength
            }
            return (nil, nil)
        }
    }
}
