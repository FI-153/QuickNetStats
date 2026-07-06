//
//  ConnectionReadersTests.swift
//  QuickNetStatsTests
//
//  Smoke + pure-logic tests for the three connection-detail readers.
//  Assertions are deliberately lenient: CI machines may have no active Wi-Fi,
//  no IPv6, or a headless network, so these confirm the readers run without
//  crashing and return well-typed values rather than asserting specific data.
//

import Testing
import Foundation
@testable import QuickNetStats

@Suite("SystemConfigReader")
struct SystemConfigReaderTests {

    @Test("snapshot() returns without crashing and yields typed arrays")
    func snapshotDoesNotCrash() {
        let snapshot = SystemConfigReader().snapshot()
        // Arrays are always present (possibly empty on CI).
        #expect(snapshot.dnsServers.count >= 0)
        #expect(snapshot.searchDomains.count >= 0)
    }

    @Test("primaryInterface, when present, looks like a BSD interface name")
    func primaryInterfaceShape() {
        let snapshot = SystemConfigReader().snapshot()
        if let primary = snapshot.primaryInterface {
            #expect(primary.range(of: "^[a-z]+[0-9]+$", options: .regularExpression) != nil)
        }
    }

    @Test("snapshot() fills the extended fields with sane types and no crash")
    func extendedSnapshotDoesNotCrash() {
        let snapshot = SystemConfigReader().snapshot()
        // The proxies struct is always present; individual proxies may be nil.
        let proxies = snapshot.proxies
        _ = (proxies.http, proxies.https, proxies.socks)
        // computerName, when present, is non-empty.
        if let name = snapshot.computerName { #expect(!name.isEmpty) }
        // ipv4ConfigMethod, when present, is a non-empty token (e.g. "DHCP").
        if let method = snapshot.ipv4ConfigMethod { #expect(!method.isEmpty) }
        // dhcpServer, when present, looks like a dotted-quad IPv4 address.
        if let server = snapshot.dhcpServer {
            #expect(server.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil)
        }
        // ipv6Router, when present, is non-empty.
        if let router = snapshot.ipv6Router { #expect(!router.isEmpty) }
    }
}

@Suite("InterfaceReader")
struct InterfaceReaderTests {

    @Test("preferredIPv6 prefers global unicast, then ULA, and never link-local")
    func preferredIPv6Order() {
        #expect(InterfaceReader.preferredIPv6(from: ["fe80::1", "2a00:1::2", "fd12::1"]) == "2a00:1::2")
        #expect(InterfaceReader.preferredIPv6(from: ["fe80::1", "fd12::1"]) == "fd12::1")
        #expect(InterfaceReader.preferredIPv6(from: ["FE80::1"]) == nil)
        #expect(InterfaceReader.preferredIPv6(from: []) == nil)
    }

    @Test("snapshot(for: lo0) returns MTU, byte and packet counters without crashing")
    func loopbackSnapshot() {
        let snapshot = InterfaceReader().snapshot(for: "lo0")
        #expect(snapshot.mtu != nil)
        #expect(snapshot.rxBytes != nil)
        #expect(snapshot.txBytes != nil)
        #expect(snapshot.rxPackets != nil)
        #expect(snapshot.txPackets != nil)
        #expect(snapshot.inErrors != nil)
        #expect(snapshot.outErrors != nil)
        #expect(snapshot.drops != nil)
    }

    @Test("snapshot for a nonexistent interface is entirely nil")
    func bogusInterfaceSnapshot() {
        let snapshot = InterfaceReader().snapshot(for: "definitely-not-real99")
        #expect(snapshot == InterfaceSnapshot())
    }

    @Test("lo0 reports no Ethernet media description")
    func loopbackHasNoMedia() {
        #expect(InterfaceReader().snapshot(for: "lo0").mediaDescription == nil)
    }

    @Test("mediaDescription maps known Ethernet subtypes with duplex", arguments: [
        (Int32(IFM_ETHER) | Int32(IFM_1000_T) | Int32(IFM_FDX), "1000baseT full-duplex"),
        (Int32(IFM_ETHER) | Int32(IFM_100_TX) | Int32(IFM_HDX), "100baseTX half-duplex"),
        (Int32(IFM_ETHER) | Int32(IFM_10_T) | Int32(IFM_FDX), "10baseT full-duplex"),
        (Int32(IFM_ETHER) | Int32(IFM_2500_T), "2500baseT"),
        (Int32(IFM_ETHER) | Int32(IFM_5000_T), "5000baseT"),
        (Int32(IFM_ETHER) | Int32(IFM_10G_T), "10GbaseT")
    ])
    func mediaDescriptionMapping(active: Int32, expected: String) {
        #expect(InterfaceReader.mediaDescription(active: active) == expected)
    }

    @Test("mediaDescription is nil for non-Ethernet and unmapped subtypes")
    func mediaDescriptionNil() {
        #expect(InterfaceReader.mediaDescription(active: 0) == nil)
        #expect(InterfaceReader.mediaDescription(active: Int32(IFM_ETHER) | 0x1f) == nil)
    }

    @Test("Extended counters and broadcast, when present on a physical interface, are well-typed")
    func physicalInterfaceExtras() {
        for name in ["en0", "en1"] {
            let snapshot = InterfaceReader().snapshot(for: name)
            // A live interface reporting bytes must also report packet counters.
            if snapshot.rxBytes != nil {
                #expect(snapshot.rxPackets != nil)
                #expect(snapshot.txPackets != nil)
            }
            // A broadcast address, when present, is a dotted-quad IPv4 literal.
            if let broadcast = snapshot.broadcastAddress {
                #expect(broadcast.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil)
            }
        }
    }
}

@Suite("WifiReader")
struct WifiReaderTests {

    @Test("A non-Wi-Fi interface (lo0) yields a nil snapshot")
    func loopbackHasNoWifi() {
        #expect(WifiReader().snapshot(for: "lo0") == nil)
    }

    @Test("A real Wi-Fi snapshot, when present, reports a plausible RSSI")
    func wifiRssiPlausible() {
        // Lenient: on CI there may be no Wi-Fi; only assert when a snapshot with
        // RSSI is actually produced. Tries the usual physical-interface names.
        for name in ["en0", "en1"] {
            if let snapshot = WifiReader().snapshot(for: name), let rssi = snapshot.rssiDBm {
                #expect((-100...0).contains(rssi))
            }
        }
    }

    @Test("interface mode maps station/IBSS/hostAP by rawValue", arguments: [
        (1, "Station"), (2, "IBSS"), (3, "Host AP")
    ])
    func modeMapping(raw: Int, expected: String) {
        #expect(WifiReader.modeText(raw) == expected)
    }

    @Test("unknown or none interface-mode raw values map to nil")
    func modeMappingNil() {
        #expect(WifiReader.modeText(0) == nil)
        #expect(WifiReader.modeText(99) == nil)
    }

    @Test("A real Wi-Fi snapshot, when present, reports a positive or nil tx power")
    func txPowerPlausible() {
        for name in ["en0", "en1"] {
            if let snapshot = WifiReader().snapshot(for: name), let power = snapshot.txPowerMw {
                #expect(power > 0)
            }
        }
    }
}

@Suite("PathReader")
struct PathReaderTests {

    @Test("snapshot returns within the timeout and yields a usable PathSnapshot")
    func snapshotReturnsPromptly() async {
        let start = ContinuousClock.now
        let snapshot = await PathReader(timeout: 2.0).snapshot(excluding: "en0")
        let elapsed = ContinuousClock.now - start
        // Must return well before the timeout ceiling (the first callback is prompt).
        #expect(elapsed < .seconds(3))
        // otherInterfaces never lists the excluded primary or a loopback.
        #expect(!snapshot.otherInterfaces.contains { $0.contains("(en0)") })
        #expect(!snapshot.otherInterfaces.contains { $0.lowercased().contains("loopback") })
    }
}
