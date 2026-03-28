//
//  SettingsTests.swift
//  QuickNetStatsTests
//
//  Tests for Settings-related enums: raw values and initializers.
//

import Testing
@testable import QuickNetStats

@Suite("Settings Enums")
struct SettingsTests {

    // MARK: - InternetNotificationBehavior

    @Test(
        "InternetNotificationBehavior raw values",
        arguments: [
            (InternetNotificationBehavior.connects, 0),
            (InternetNotificationBehavior.disconnects, 1),
            (InternetNotificationBehavior.changes, 2),
        ]
    )
    func internetBehaviorRawValues(behavior: InternetNotificationBehavior, expected: Int) {
        #expect(behavior.rawValue == expected)
    }

    @Test("InternetNotificationBehavior initializes from valid raw value")
    func internetBehaviorFromRaw() {
        let behavior = InternetNotificationBehavior(rawValue: 1)
        #expect(behavior == .disconnects)
    }

    @Test("InternetNotificationBehavior returns nil for invalid raw value")
    func internetBehaviorInvalidRaw() {
        let behavior = InternetNotificationBehavior(rawValue: 99)
        #expect(behavior == nil)
    }

    @Test("InternetNotificationBehavior has 3 cases")
    func internetBehaviorCaseCount() {
        #expect(InternetNotificationBehavior.allCases.count == 3)
    }

    // MARK: - LinkQualityNotificationBehavior

    @Test(
        "LinkQualityNotificationBehavior raw values",
        arguments: [
            (LinkQualityNotificationBehavior.worsens, 0),
            (LinkQualityNotificationBehavior.improves, 1),
            (LinkQualityNotificationBehavior.changes, 2),
        ]
    )
    func qualityBehaviorRawValues(behavior: LinkQualityNotificationBehavior, expected: Int) {
        #expect(behavior.rawValue == expected)
    }

    @Test("LinkQualityNotificationBehavior initializes from valid raw value")
    func qualityBehaviorFromRaw() {
        let behavior = LinkQualityNotificationBehavior(rawValue: 0)
        #expect(behavior == .worsens)
    }

    @Test("LinkQualityNotificationBehavior returns nil for invalid raw value")
    func qualityBehaviorInvalidRaw() {
        let behavior = LinkQualityNotificationBehavior(rawValue: 99)
        #expect(behavior == nil)
    }
}
