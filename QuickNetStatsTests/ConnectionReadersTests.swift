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

    @Test("snapshot(for: lo0) returns an MTU and byte counters without crashing")
    func loopbackSnapshot() {
        let snapshot = InterfaceReader().snapshot(for: "lo0")
        #expect(snapshot.mtu != nil)
        #expect(snapshot.rxBytes != nil)
        #expect(snapshot.txBytes != nil)
    }

    @Test("snapshot for a nonexistent interface is entirely nil")
    func bogusInterfaceSnapshot() {
        let snapshot = InterfaceReader().snapshot(for: "definitely-not-real99")
        #expect(snapshot == InterfaceSnapshot())
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
}
