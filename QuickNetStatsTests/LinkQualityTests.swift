//
//  LinkQualityTests.swift
//  QuickNetStatsTests
//
//  Tests for LinkQuality enum: raw values, descriptions, and CaseIterable conformance.
//

import Testing
@testable import QuickNetStats

@Suite("LinkQuality Enum")
struct LinkQualityTests {

    @Test(
        "description returns correct display string",
        arguments: [
            (LinkQuality.good, "Good"),
            (LinkQuality.moderate, "Moderate"),
            (LinkQuality.minimal, "Minimal"),
            (LinkQuality.unknown, "Unknown"),
        ]
    )
    func descriptionMapping(quality: LinkQuality, expected: String) {
        #expect(quality.description == expected)
    }

    @Test(
        "raw values reflect ordering (good > moderate > minimal > unknown)",
        arguments: [
            (LinkQuality.good, 3),
            (LinkQuality.moderate, 2),
            (LinkQuality.minimal, 1),
            (LinkQuality.unknown, 0),
        ]
    )
    func rawValueOrdering(quality: LinkQuality, expectedRaw: Int) {
        #expect(quality.rawValue == expectedRaw)
    }

    @Test("allCases contains exactly four cases")
    func allCasesCount() {
        #expect(LinkQuality.allCases.count == 4)
    }

    @Test("id matches rawValue for Identifiable conformance")
    func identifiableConformance() {
        for quality in LinkQuality.allCases {
            #expect(quality.id == quality.rawValue)
        }
    }
}
