//
//  LinkQualityNotifierTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

@Suite("LinkQualityNotifier")
struct LinkQualityNotifierTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private let good = NetworkStats.mockGoodWifiConnection
    private let moderate = NetworkStats.mockModerateWifiConnection
    private let minimal = NetworkStats.mockBadWifiConnection
    private let offline = NetworkStats.mockDisconnected
    private let goodEthernet = NetworkStats.mockGoodEthConnection

    private var unknownWifi: NetworkStats {
        var stats = NetworkStats.mockGoodWifiConnection
        stats.linkQuality = .unknown
        return stats
    }

    @Test("First known sample becomes the baseline without emitting")
    func firstSampleIsBaseline() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        #expect(notifier.baseline == .init(quality: .good, interface: .wifi))
        #expect(notifier.evaluate(now: at(1000)) == nil)
        #expect(notifier.nextDeadline == nil)
    }

    @Test("Unknown quality samples are ignored")
    func unknownIsIgnored() {
        var notifier = LinkQualityNotifier()
        notifier.observe(unknownWifi, now: t0)
        #expect(notifier.baseline == nil)
        notifier.observe(good, now: at(1))
        notifier.observe(unknownWifi, now: at(2))
        #expect(notifier.baseline?.quality == .good)
        #expect(notifier.candidate == nil)
    }

    @Test("Unknown arriving mid-candidate does not cancel or restart it")
    func unknownDoesNotDisturbCandidate() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(moderate, now: at(10))
        notifier.observe(unknownWifi, now: at(20))
        #expect(notifier.candidate == .init(quality: .moderate, since: at(10)))
        #expect(notifier.evaluate(now: at(40)) == LinkQualityChange(old: .good, new: .moderate))
    }

    @Test("Disconnect resets state without emitting")
    func disconnectResets() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(moderate, now: at(1))
        notifier.observe(offline, now: at(2))
        #expect(notifier.baseline == nil)
        #expect(notifier.candidate == nil)
        #expect(notifier.evaluate(now: at(100)) == nil)
    }

    @Test("A known sample after reconnect becomes the baseline silently")
    func reconnectBecomesBaselineSilently() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(offline, now: at(1))
        notifier.observe(moderate, now: at(2))
        #expect(notifier.baseline == .init(quality: .moderate, interface: .wifi))
        #expect(notifier.evaluate(now: at(100)) == nil)
    }

    @Test("Interface change resets and adopts the new interface as baseline")
    func interfaceChangeResets() {
        var notifier = LinkQualityNotifier()
        notifier.observe(moderate, now: t0)
        notifier.observe(goodEthernet, now: at(1))
        #expect(notifier.baseline == .init(quality: .good, interface: .ethernet))
        #expect(notifier.candidate == nil)
        #expect(notifier.evaluate(now: at(100)) == nil)
    }

    @Test("A swing shorter than the stability window emits nothing")
    func shortSwingSuppressed() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(moderate, now: at(1))
        notifier.observe(good, now: at(20))
        #expect(notifier.candidate == nil)
        #expect(notifier.evaluate(now: at(100)) == nil)
    }

    @Test("A change sustained past the stability window emits exactly once")
    func sustainedChangeEmitsOnce() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(moderate, now: at(1))
        #expect(notifier.evaluate(now: at(30)) == nil)
        #expect(notifier.evaluate(now: at(31)) == LinkQualityChange(old: .good, new: .moderate))
        #expect(notifier.baseline?.quality == .moderate)
        #expect(notifier.evaluate(now: at(32)) == nil)
    }

    @Test("A different candidate level restarts the stability window")
    func candidateLevelChangeRestarts() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(moderate, now: at(1))
        notifier.observe(minimal, now: at(20))
        #expect(notifier.evaluate(now: at(31)) == nil)
        #expect(notifier.evaluate(now: at(50)) == LinkQualityChange(old: .good, new: .minimal))
    }

    @Test("Repeating the candidate level keeps the original start time")
    func sameCandidateKeepsStart() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(moderate, now: at(1))
        notifier.observe(moderate, now: at(25))
        #expect(notifier.candidate?.since == at(1))
    }

    @Test("Changes inside the cooldown collapse into one emission at cooldown end")
    func cooldownCollapsesChanges() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(moderate, now: at(1))
        #expect(notifier.evaluate(now: at(31)) != nil)
        notifier.recordDelivery(at: at(31))

        notifier.observe(minimal, now: at(60))
        #expect(notifier.evaluate(now: at(100)) == nil)
        #expect(notifier.nextDeadline == at(331))
        #expect(notifier.evaluate(now: at(331)) == LinkQualityChange(old: .moderate, new: .minimal))
    }

    @Test("Returning to baseline inside the cooldown emits nothing")
    func revertInsideCooldownIsSilent() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(moderate, now: at(1))
        _ = notifier.evaluate(now: at(31))
        notifier.recordDelivery(at: at(31))

        notifier.observe(good, now: at(60))
        notifier.observe(moderate, now: at(120))
        #expect(notifier.candidate == nil)
        #expect(notifier.nextDeadline == nil)
        #expect(notifier.evaluate(now: at(400)) == nil)
    }

    @Test("nextDeadline is the stability deadline when no cooldown is active")
    func nextDeadlineWithoutCooldown() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(moderate, now: at(5))
        #expect(notifier.nextDeadline == at(35))
    }

    @Test("Not recording a delivery leaves the cooldown unconsumed")
    func undeliveredChangeDoesNotStartCooldown() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(moderate, now: at(1))
        _ = notifier.evaluate(now: at(31))

        notifier.observe(good, now: at(40))
        #expect(notifier.evaluate(now: at(70)) == LinkQualityChange(old: .moderate, new: .good))
    }

    @Test("Cooldown survives a reconnect; reset() clears it")
    func cooldownPersistsAcrossReconnect() {
        var notifier = LinkQualityNotifier()
        notifier.observe(good, now: t0)
        notifier.observe(moderate, now: at(1))
        _ = notifier.evaluate(now: at(31))
        notifier.recordDelivery(at: at(31))
        notifier.observe(offline, now: at(40))
        #expect(notifier.lastNotifiedAt == at(31))
        notifier.reset()
        #expect(notifier.lastNotifiedAt == nil)
        #expect(notifier.baseline == nil)
    }
}
