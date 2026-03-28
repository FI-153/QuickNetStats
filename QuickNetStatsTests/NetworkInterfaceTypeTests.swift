//
//  NetworkInterfaceTypeTests.swift
//  QuickNetStatsTests
//
//  Tests for NetworkInterfaceType enum raw values.
//

import Testing
@testable import QuickNetStats

@Suite("NetworkInterfaceType Enum")
struct NetworkInterfaceTypeTests {

    @Test(
        "raw values match expected display strings",
        arguments: [
            (NetworkInterfaceType.wifi, "Wifi"),
            (NetworkInterfaceType.cellular, "Cellular"),
            (NetworkInterfaceType.ethernet, "Ethernet"),
            (NetworkInterfaceType.other, "Other"),
            (NetworkInterfaceType.none, "None"),
        ]
    )
    func rawValues(type: NetworkInterfaceType, expected: String) {
        #expect(type.rawValue == expected)
    }
}
