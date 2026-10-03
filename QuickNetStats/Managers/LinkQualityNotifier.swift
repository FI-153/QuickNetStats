//
//  LinkQualityNotifier.swift
//  QuickNetStats
//

import Foundation
import os

/// A confirmed link-quality transition worth notifying about.
struct LinkQualityChange: Equatable {
    /// The previously confirmed quality.
    let old: LinkQuality
    /// The newly confirmed quality.
    let new: LinkQuality
}

/// Decides when a link-quality change is worth a notification: only between two known
/// readings on the same connected interface, after the new level has held for
/// `stabilityWindow`, and no sooner than `cooldown` after the last delivered one.
/// Time is always injected so the rules are deterministic in tests.
struct LinkQualityNotifier {

    // MARK: - Types

    /// The last confirmed quality on the current connection.
    struct Baseline: Equatable {
        var quality: LinkQuality
        var interface: NetworkInterfaceType
    }

    /// A differing quality level waiting out the stability window.
    struct Candidate: Equatable {
        var quality: LinkQuality
        var since: Date
    }

    // MARK: - Properties

    /// How long a new level must persist before it counts as a change.
    let stabilityWindow: TimeInterval

    /// Minimum spacing between delivered quality notifications.
    let cooldown: TimeInterval

    /// The last confirmed quality; `nil` until a known sample arrives on a connected interface.
    private(set) var baseline: Baseline?

    /// The pending level change, if any.
    private(set) var candidate: Candidate?

    /// When a quality notification was last delivered; survives reconnects, cleared only by `reset()`.
    private(set) var lastNotifiedAt: Date?

    // MARK: - Initializers

    init(stabilityWindow: TimeInterval = 30, cooldown: TimeInterval = 300) {
        self.stabilityWindow = stabilityWindow
        self.cooldown = cooldown
    }

    // MARK: - Computed Properties

    /// When `evaluate(now:)` should next be called: the later of the candidate's stability
    /// deadline and the cooldown end. `nil` when there is no candidate.
    var nextDeadline: Date? {
        guard let candidate else { return nil }
        let stableAt = candidate.since.addingTimeInterval(stabilityWindow)
        guard let lastNotifiedAt else { return stableAt }
        return max(stableAt, lastNotifiedAt.addingTimeInterval(cooldown))
    }

    // MARK: - State Updates

    /// Feeds a new network snapshot. Disconnects and interface changes reset the baseline,
    /// unknown qualities are ignored, and a differing known quality starts (or keeps) a candidate.
    mutating func observe(_ stats: NetworkStats, now: Date) {
        guard stats.isConnected else {
            clearConnectionState(reason: "disconnected")
            return
        }
        
        if let baseline, baseline.interface != stats.interfaceType {
            clearConnectionState(reason: "interface changed")
        }
        
        guard let quality = stats.linkQuality, quality != .unknown else { return }

        guard let baseline else {
            self.baseline = Baseline(quality: quality, interface: stats.interfaceType)
            Logger.notifications.debug("Quality baseline set: \(quality.description, privacy: .public)")
            return
        }

        if quality == baseline.quality {
            if candidate != nil {
                Logger.notifications.debug("Quality candidate dropped: back to \(quality.description, privacy: .public)")
            }
            candidate = nil
            
        } else if candidate?.quality != quality {
            candidate = Candidate(quality: quality, since: now)
            Logger.notifications.debug("Quality candidate started: \(quality.description, privacy: .public)")
            
        }
    }

    /// Returns the baseline-to-candidate change once the candidate has been stable for
    /// `stabilityWindow` and the cooldown has elapsed, promoting the candidate to baseline.
    mutating func evaluate(now: Date) -> LinkQualityChange? {
        guard let candidate, let baseline,
              now.timeIntervalSince(candidate.since) >= stabilityWindow else { return nil }

        if let lastNotifiedAt, now.timeIntervalSince(lastNotifiedAt) < cooldown {
            Logger.notifications.debug("Quality change held by cooldown")
            return nil
        }

        self.baseline = Baseline(quality: candidate.quality, interface: baseline.interface)
        
        self.candidate = nil
        return LinkQualityChange(old: baseline.quality, new: candidate.quality)
    }

    /// Starts the cooldown. Kept separate from `evaluate` so a change filtered out by the
    /// user's behavior setting updates the baseline without consuming the cooldown.
    mutating func recordDelivery(at date: Date) {
        lastNotifiedAt = date
    }

    /// Clears all state, including the cooldown.
    mutating func reset() {
        baseline = nil
        candidate = nil
        lastNotifiedAt = nil
    }

    /// Drops the baseline and candidate but keeps the cooldown.
    private mutating func clearConnectionState(reason: String) {
        guard baseline != nil || candidate != nil else { return }
        baseline = nil
        candidate = nil
        Logger.notifications.debug("Quality baseline reset: \(reason, privacy: .public)")
    }
}
