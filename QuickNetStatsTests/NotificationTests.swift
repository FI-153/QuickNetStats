//
//  NotificationTests.swift
//  QuickNetStatsTests
//
//  Tests for Notification model: comparison, equality, subclass priorities.
//

import Testing
import Foundation
@testable import QuickNetStats

/// Type alias to disambiguate from Foundation.Notification
typealias AppNotification = QuickNetStats.Notification

@Suite("Notification Model")
struct NotificationTests {

    let now = Date()

    // MARK: - Subclass priorities

    @Test("InternetStatusNotification has priority 1")
    func internetStatusPriority() {
        let n = InternetStatusNotification(title: "Test", body: "Body", created: now)
        #expect(n.priority == 1)
    }

    @Test("InterfaceChangesStatusNotification has priority 2")
    func interfaceChangesPriority() {
        let n = InterfaceChangesStatusNotification(title: "Test", body: "Body", created: now)
        #expect(n.priority == 2)
    }

    @Test("LinkQualityStatusNotification has priority 3")
    func linkQualityPriority() {
        let n = LinkQualityStatusNotification(title: "Test", body: "Body", created: now)
        #expect(n.priority == 3)
    }

    // MARK: - Comparable: priority ordering

    @Test("Lower priority value sorts first")
    func lowerPrioritySortsFirst() {
        let internet = InternetStatusNotification(title: "A", body: "", created: now)
        let quality = LinkQualityStatusNotification(title: "A", body: "", created: now)
        #expect(internet < quality)
    }

    @Test("Sorting a mixed array puts internet status first")
    func sortingByPriority() {
        let quality = LinkQualityStatusNotification(title: "Q", body: "", created: now)
        let iface = InterfaceChangesStatusNotification(title: "I", body: "", created: now)
        let internet = InternetStatusNotification(title: "N", body: "", created: now)

        let notifications: [AppNotification] = [quality, iface, internet]
        let sorted = notifications.sorted()
        #expect(sorted[0].priority == 1)
        #expect(sorted[1].priority == 2)
        #expect(sorted[2].priority == 3)
    }

    // MARK: - Comparable: date tiebreaker

    @Test("When priorities are equal, earlier date sorts first")
    func dateTiebreaker() {
        let earlier = InternetStatusNotification(title: "A", body: "", created: now)
        let later = InternetStatusNotification(
            title: "A", body: "", created: now.addingTimeInterval(1)
        )
        #expect(earlier < later)
    }

    // MARK: - Comparable: title tiebreaker

    @Test("When priority and date are equal, alphabetically earlier title sorts first")
    func titleTiebreaker() {
        let a = InternetStatusNotification(title: "Alpha", body: "", created: now)
        let b = InternetStatusNotification(title: "Beta", body: "", created: now)
        #expect(a < b)
    }

    // MARK: - Equatable: UUID-based

    @Test("Two notifications with different UUIDs are not equal")
    func differentUUIDsNotEqual() {
        let a = AppNotification(title: "Same", body: "Same", priority: 1, created: now)
        let b = AppNotification(title: "Same", body: "Same", priority: 1, created: now)
        #expect(a != b)
    }

    @Test("A notification is equal to itself")
    func sameInstanceIsEqual() {
        let a = AppNotification(title: "Test", body: "Body", priority: 1, created: now)
        #expect(a == a)
    }
}
