//
//  DataRateTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

@Suite("RateUnit")
struct RateUnitTests {

    @Test(
        "Raw values match their unit abbreviation",
        arguments: [
            (RateUnit.bitsPerSecond, "bps"),
            (RateUnit.bytesPerSecond, "B/s"),
        ]
    )
    func rawValues(unit: RateUnit, expected: String) {
        #expect(unit.rawValue == expected)
    }

    @Test("id matches rawValue for each unit")
    func idMatchesRawValue() {
        for unit in RateUnit.allCases {
            #expect(unit.id == unit.rawValue)
        }
    }

    @Test("allCases contains exactly the two families in order")
    func allCasesOrder() {
        #expect(RateUnit.allCases == [.bitsPerSecond, .bytesPerSecond])
    }

    @Test("displayName describes the family with a sample multiple")
    func displayNames() {
        #expect(RateUnit.bitsPerSecond.displayName == "Bits per second (Mbps)")
        #expect(RateUnit.bytesPerSecond.displayName == "Bytes per second (MB/s)")
    }
}

@Suite("DataRate")
struct DataRateTests {

    // MARK: - Conversions

    @Test("bitsToBytes divides by 8")
    func bitsToBytes() {
        #expect(DataRate.bitsToBytes(8) == 1)
        #expect(DataRate.bitsToBytes(210_000_000) == 26_250_000)
    }

    @Test("bytesToBits multiplies by 8")
    func bytesToBits() {
        #expect(DataRate.bytesToBits(1) == 8)
        #expect(DataRate.bytesToBits(26_250_000) == 210_000_000)
    }

    @Test("conversions round-trip losslessly")
    func conversionRoundTrip() {
        #expect(DataRate.bytesToBits(DataRate.bitsToBytes(1_000_000)) == 1_000_000)
        #expect(DataRate.bitsToBytes(DataRate.bytesToBits(500_000)) == 500_000)
    }

    // MARK: - Bits family formatting

    @Test(
        "Bits values scale to the largest multiple with stripped decimals",
        arguments: [
            (0.0, "0 bps"),
            (999.0, "999 bps"),
            (1_000.0, "1 Kbps"),
            (1_500.0, "1.5 Kbps"),
            (866_000_000.0, "866 Mbps"),
            (1_000_000_000.0, "1 Gbps"),
            (2_500_000_000.0, "2.5 Gbps"),
        ]
    )
    func bitsFormatting(input: Double, expected: String) {
        #expect(DataRate.text(bitsPerSecond: input, in: .bitsPerSecond) == expected)
    }

    // MARK: - Bytes family formatting

    @Test(
        "Bytes values scale to the largest multiple with stripped decimals",
        arguments: [
            (0.0, "0 B/s"),
            (0.13, "0.13 B/s"),
            (999.0, "999 B/s"),
            (1_000.0, "1 KB/s"),
            (1_000_000.0, "1 MB/s"),
            (1_000_000_000.0, "1 GB/s"),
            (26_250_000.0, "26.25 MB/s"),
        ]
    )
    func bytesFormatting(input: Double, expected: String) {
        #expect(DataRate.text(bytesPerSecond: input, in: .bytesPerSecond) == expected)
    }

    // MARK: - Cross-family display (convert then format)

    @Test("A bits rate displayed in bytes converts before scaling")
    func bitsShownInBytes() {
        // Canonical example: 210 Mbps link speed shown in bytes.
        #expect(DataRate.text(bitsPerSecond: 210_000_000, in: .bytesPerSecond) == "26.25 MB/s")
        #expect(DataRate.text(bitsPerSecond: 866_000_000, in: .bytesPerSecond) == "108.25 MB/s")
    }

    @Test("A bytes rate displayed in bits converts before scaling")
    func bytesShownInBits() {
        // 1 GB/s == 8 Gbps.
        #expect(DataRate.text(bytesPerSecond: 1_000_000_000, in: .bitsPerSecond) == "8 Gbps")
    }
}
