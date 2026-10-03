# Plan: Fix Link Quality Notification Spam

> **Date**: 2026-10-03
> **Scope**: Move link-quality notification decisions out of the 1s settle window into a dedicated, time-injectable state machine with a stability window and cooldown; add diagnostic logging of path updates
> **Prerequisite**: None (builds on `debounce-notifications.md` and `better-disconnection-detection.md`)

---

## Context

Since updating to macOS 27 the app fires far too many link-quality notifications. Investigation of
the current pipeline (`NetworkStatsManager` → `NotificationsManager.checkForNotifications` → 1s
settle → `evaluateSettledState`) found three defects in our own code:

1. **Disconnects leak as "Network Quality Worsened".** Every disconnect — a real path drop or a
   single failed 15s reachability poll — publishes `NetworkStats.defaultOffline`, whose quality is
   `.unknown` (raw value 0). `checkLinkQualityChanges` sees `good(3) → unknown(0)` and reports a
   worsening. With the default internet behavior `.connects`, the disconnect itself produces no
   candidate, so the quality notification is the one delivered. The reconnect then delivers
   "Internet Connected". Each blip ≈ two notifications, one mislabelled.
2. **`.unknown` is ordered as the worst quality.** Any transition between a real level and
   `.unknown` (wake, interface churn, the system not having measured yet) notifies.
3. **No hysteresis for genuine oscillation.** The only filter is the shared 1s settle window and
   there is no cooldown (removed for all categories in `debounce-notifications.md`). Quality
   oscillating `good ↔ moderate` with a period above 1s notifies on every edge.

What was *not* established: the macOS 27 SDK's `NWPath.LinkQuality` still has the same four cases
(no new case falling into `.unknown`), and a 90s `NWPathMonitor` probe on a stable Wi-Fi link saw a
single update with constant `good`. Whether macOS 27 makes quality oscillate more is unverified —
the diagnostic logging below exists to answer that.

---

## Overview

```
NWPathMonitor ──► NetworkStatsManager.handlePathUpdate ──[log: network]──┐
                                                                          ▼
                                              publishStats(newStats)
                                     first update │            │ later updates
                                                  ▼            ▼
                         NotificationsManager.primeLinkQuality  NotificationsManager.checkForNotifications
                                                  │            │
                                                  │            ├──► 1s settle window ──► internet / interface
                                                  │            │    (quality removed)     notification
                                                  ▼            ▼
                                        LinkQualityNotifier.observe(stats, now)
                                                  │
                                       nextDeadline ──► qualityTask (single, rescheduled)
                                                  │
                                                  ▼
                                        LinkQualityNotifier.evaluate(now) ──[log: notifications]
                                                  │ (old, new)?
                                                  ▼
                              checkLinkQualityChanges (behavior filter + title) ──► notify
```

---

## Design

### New type: `LinkQualityNotifier`

New file `QuickNetStats/Managers/LinkQualityNotifier.swift`. A plain struct with no timers and no
system dependencies; time is always passed in as `now: Date`, so every rule is deterministically
unit-testable without sleeping.

**Constants**

- `stabilityWindow: TimeInterval = 30` — a new level must persist this long before it counts.
- `cooldown: TimeInterval = 300` — minimum spacing between delivered quality notifications.

Both are fixed in code (no user setting). They are init parameters with these defaults so tests can
use them by name.

**State**

- `baseline: (quality: LinkQuality, interface: NetworkInterfaceType)?` — last confirmed quality on
  the current connection.
- `candidate: (quality: LinkQuality, since: Date)?` — a differing level waiting out the stability
  window.
- `lastNotifiedAt: Date?` — when a quality notification was last emitted.

**`mutating func observe(_ stats: NetworkStats, now: Date)`**

Rules, evaluated in order:

| Input | Effect |
|-------|--------|
| `!stats.isConnected`, or `stats.interfaceType != baseline.interface` | Clear `baseline` and `candidate`. Never notifies. |
| Connected, quality `.unknown` or `nil` | Ignore the sample entirely; state unchanged. |
| No `baseline`, known quality | Sample becomes `baseline` silently (launch, reconnect, interface switch). |
| Quality `== baseline.quality` | Clear `candidate` (transient swing). |
| Quality `!= baseline.quality` | If no candidate or candidate level differs → `candidate = (quality, now)`. Same level → keep original `since`. |

An interface change is covered by the interface-change notification; resetting rather than
comparing across interfaces avoids double notifications.

**`mutating func evaluate(now: Date) -> (old: LinkQuality, new: LinkQuality)?`**

- No candidate, or `now - candidate.since < stabilityWindow` → `nil`.
- Cooldown elapsed (`lastNotifiedAt == nil` or `now - lastNotifiedAt >= cooldown`) → return
  `(baseline.quality, candidate.quality)`, promote candidate to baseline, clear candidate.
  `lastNotifiedAt` is *not* set here (see `recordDelivery`).
- Inside cooldown → `nil`; the candidate is kept and re-evaluated when the cooldown ends. The
  comparison is always baseline vs. the *current* candidate, so `good → moderate → minimal` within a
  cooldown yields a single "Worsened" (good → minimal), and a return to baseline yields nothing.

**`mutating func recordDelivery(at: Date)`** — sets `lastNotifiedAt`. The manager calls it only
when a notification is actually sent. When the user's behavior setting (`.improves` / `.worsens`)
filters out an emitted change, the baseline is still promoted (done by `evaluate`) but the cooldown
is not consumed.

**`var nextDeadline: Date?`** — when the manager should next call `evaluate`:
`max(candidate.since + stabilityWindow, lastNotifiedAt + cooldown)` when a candidate exists,
otherwise `nil`.

**`mutating func reset()`** — clears all state including `lastNotifiedAt`.

### Changes to `NotificationsManager`

- Owns `private var linkQualityNotifier = LinkQualityNotifier()` and
  `private var qualityTask: Task<Void, Never>?`.
- `evaluateSettledState` no longer calls `checkLinkQualityChanges`; the 1s settle window only
  decides internet and interface notifications.
- `checkForNotifications(oldStats:newStats:)`:
  - If notifications are globally disabled: `linkQualityNotifier.reset()`, cancel `qualityTask`,
    return (existing early return, extended).
  - Otherwise, in addition to the existing settle logic: `linkQualityNotifier.observe(newStats,
    now: Date())` then `scheduleQualityEvaluation()`.
- `scheduleQualityEvaluation()`: cancels `qualityTask`; if `nextDeadline` is non-nil, starts a task
  sleeping until it, then calls `evaluateLinkQuality()`.
- `evaluateLinkQuality()`: `evaluate(now:)`; on a result, pass the raw values through the existing
  `checkLinkQualityChanges(oldQuality:newQuality:defaults:)` (unchanged — applies the behavior
  filter and builds the title). If it returns a notification → `notify(_:)` and
  `recordDelivery(at:)`. Always reschedule afterwards (a cooldown-held candidate needs a new
  deadline).
- New `primeLinkQuality(_ stats: NetworkStats)`: `reset()` then `observe(stats, now: Date())`.
  Establishes the baseline from the launch snapshot.
- Test seam: `var now: () -> Date = Date.init`, matching the existing `defaults` /
  `suppressSystemNotifications` overridable-property pattern.

### Changes to `NetworkStatsManager`

- `publishStats`: in the `isFirstUpdate` branch, call
  `NotificationsManager.shared.primeLinkQuality(newStats)` before returning. Without it the notifier
  would have no baseline after launch and would silently adopt the first later quality change as
  its baseline, missing it. `refresh()` already sets `isFirstUpdate = true`, so a monitor restart
  re-primes.
- `handlePathUpdate`: emit the diagnostic log line (below).

### Diagnostic logging

The project has no logging today; introduce `os.Logger`:

- `Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.federicoimberti.quicknetstats",
  category: "network")` in `NetworkStatsManager.handlePathUpdate`, at `.info`: status, interface
  type, connection technology, link quality, `isExpensive`, `isConstrained`. All values are
  interpolated with `privacy: .public` — none are sensitive (no SSIDs, addresses, or names).
- `category: "notifications"` in `LinkQualityNotifier` / `NotificationsManager`, at `.debug`:
  baseline set/reset, candidate started/dropped, emitted, held by cooldown, filtered by behavior.
- Inspect with:
  `log stream --predicate 'subsystem == "com.federicoimberti.quicknetstats.dev"' --level debug`

### Testing

- **New `LinkQualityNotifierTests`** (pure, injected `Date`s, no sleeps):
  - first known sample becomes baseline without emitting;
  - `.unknown` samples are ignored (do not reset baseline, do not cancel a candidate);
  - disconnect resets; a known sample after reconnect becomes baseline silently;
  - interface change resets without emitting;
  - swing shorter than 30s then back to baseline emits nothing;
  - change sustained ≥30s emits exactly once with correct `(old, new)`;
  - candidate level change restarts the window;
  - multiple changes inside cooldown collapse into one emission at cooldown end;
  - return to baseline inside cooldown emits nothing;
  - `nextDeadline` values for candidate-only and cooldown-held cases;
  - not calling `recordDelivery` leaves the cooldown unconsumed.
- **`NotificationsManagerSettleTests`**: add "disconnect with `.connects` behavior delivers
  nothing" (today delivers "Network Quality Worsened").
- **`NetworkStatsManagerTests`**: first update primes the notifier.
- Existing `checkLinkQualityChanges` unit tests remain valid and unchanged.

### No changes to

- `Settings`, `NotificationView` (behavior picker kept as-is), `AppNotification` priorities,
  notification titles/bodies, the internet/interface settle logic, `InternetReachabilityChecker`.

---

## Edge Cases & Constraints

- **Sleep/wake**: path goes unsatisfied → reset; first known sample after wake becomes baseline
  silently. No quality notification on wake.
- **VPN up/down**: produces extra path updates but the primary interface type is unchanged; same
  quality → no effect.
- **Failed reachability poll**: publishes `defaultOffline` → reset, so a captive/upstream outage
  never surfaces as a quality notification (only per the internet behavior setting).
- **Change during cooldown that reverts before cooldown ends**: suppressed by design.
- **Real degradation suppressed up to 5 min after a previous quality notification**: accepted
  trade-off; the menu bar still shows live quality because only notifications are gated.
- **Notifications toggled off then on**: notifier was reset while off; next known sample becomes
  baseline silently.
- **macOS < 26**: `linkQuality` is `nil` → always ignored; notifier never emits.
- **Demo mode** (`--demo`): the monitor is never started, so `publishStats` is never called;
  unaffected.
- **`qualityTask` timing**: deadline sleeps use wall-clock `Date`; a system sleep during the wait
  causes a late fire, which is harmless (evaluate re-checks with the real `now`, and wake resets
  state anyway).
- **Unverified hypothesis**: macOS 27 oscillation frequency. The logging lets us confirm it; the
  fix is correct regardless because defects 1 and 2 exist on macOS 26 too.

---

## Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) and
> superpowers:test-driven-development. Check each box (`- [x]`) immediately after completing it.
> **Never commit** — the user commits manually. Build and test through the Xcode MCP server
> (`mcp__xcode__*`, tab identifier from `XcodeListWindows`); fallback:
> `caffeinate -dims env DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'`.
> Invoke `swift-testing-expert:swift-testing-expert` before writing tests (if available).

**Goal:** Link-quality notifications fire only for sustained (≥30s) quality changes on a stable
connection, at most once per 5 min; disconnects never produce quality notifications.

**Architecture:** A pure `LinkQualityNotifier` struct (time injected) owned by
`NotificationsManager`, fed every published `NetworkStats`; the 1s settle window stops handling
quality. `os.Logger` categories `network` and `notifications` provide diagnostics.

**Tech Stack:** Swift 5.9, SwiftUI app, Network.framework, Swift Testing, `os.Logger`.
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (all new types are implicitly `@MainActor`).
The project uses file-system-synchronized groups: new files under `QuickNetStats/` and
`QuickNetStatsTests/` are picked up automatically — no `project.pbxproj` edits.

**Spec:** this file (sections above).

### Global Constraints

- `stabilityWindow = 30` s, `cooldown = 300` s, fixed in code (init defaults).
- No changes to `Settings`, `NotificationView`, `AppNotification` priorities, notification titles/bodies.
- macOS 13 deployment target; `linkQuality` only populated on macOS 26+ (`nil` otherwise).
- Log values use `privacy: .public`; never log SSIDs, IPs, or names.
- Follow `context/styling/formatting.md`; minimal comments (only non-obvious *why*).
- `swiftlint lint` must be clean for touched files.

### Review Focus

- Reconnect after a failed reachability poll on the same interface → no quality notification (baseline re-established silently). Pinned in Task 1 (`reconnectBecomesBaselineSilently`).
- `.unknown` arriving mid-candidate must not cancel or restart the candidate. Pinned in Task 1 (`unknownDoesNotDisturbCandidate`).
- Behavior filter `.improves` with a worsening → baseline updated, cooldown not consumed, so a later improvement notifies immediately once stable. Pinned in Task 2 (`filteredChangeDoesNotConsumeCooldown`).
- Singleton test isolation: a pending `qualityTask` from one test must not deliver into another. Handled by `resetLinkQualityTracking()` in test `restore`; Task 2.
- Disconnect with default `.connects` internet behavior → nothing delivered. Pinned in Task 2 (`disconnectWithConnectsBehaviorDeliversNothing`).

### File Map

- Create: `QuickNetStats/Managers/LinkQualityNotifier.swift` — state machine.
- Create: `QuickNetStats/Managers/Logger+App.swift` — `Logger.network`, `Logger.notifications`.
- Modify: `QuickNetStats/Managers/NotificationsManager.swift` — own notifier, scheduling, remove quality from settle.
- Modify: `QuickNetStats/Managers/NetworkStatsManager.swift` — prime on first update, path log line.
- Create: `QuickNetStatsTests/LinkQualityNotifierTests.swift`.
- Modify: `QuickNetStatsTests/NotificationsManagerTests.swift`, `QuickNetStatsTests/NetworkStatsManagerTests.swift`.

---

### Task 1: `LinkQualityNotifier` state machine + loggers

**Files:** Create `QuickNetStats/Managers/Logger+App.swift`, `QuickNetStats/Managers/LinkQualityNotifier.swift`, `QuickNetStatsTests/LinkQualityNotifierTests.swift`.

**Interfaces — Produces:**
```swift
struct LinkQualityChange: Equatable { let old: LinkQuality; let new: LinkQuality }
struct LinkQualityNotifier {
    struct Baseline: Equatable { var quality: LinkQuality; var interface: NetworkInterfaceType }
    struct Candidate: Equatable { var quality: LinkQuality; var since: Date }
    init(stabilityWindow: TimeInterval = 30, cooldown: TimeInterval = 300)
    private(set) var baseline: Baseline?
    private(set) var candidate: Candidate?
    private(set) var lastNotifiedAt: Date?
    var nextDeadline: Date? { get }
    mutating func observe(_ stats: NetworkStats, now: Date)
    mutating func evaluate(now: Date) -> LinkQualityChange?
    mutating func recordDelivery(at date: Date)
    mutating func reset()
}
extension Logger { static let network: Logger; static let notifications: Logger }
```
(`LinkQualityChange` replaces the spec's `(old, new)` tuple so tests can use `#expect(==)`.)

- [x] **Step 1: Write the failing tests** in `QuickNetStatsTests/LinkQualityNotifierTests.swift`:

```swift
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
```

- [x] **Step 2: Run the tests and confirm they fail to compile** (`RunSomeTests` on `LinkQualityNotifierTests`). Expected: "cannot find 'LinkQualityNotifier' in scope".

- [x] **Step 3: Create `QuickNetStats/Managers/Logger+App.swift`:**

```swift
//
//  Logger+App.swift
//  QuickNetStats
//

import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.federicoimberti.quicknetstats"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
```

- [x] **Step 4: Create `QuickNetStats/Managers/LinkQualityNotifier.swift`:**

```swift
//
//  LinkQualityNotifier.swift
//  QuickNetStats
//

import Foundation
import os

struct LinkQualityChange: Equatable {
    let old: LinkQuality
    let new: LinkQuality
}

/// Decides when a link-quality change is worth a notification: only between two known
/// readings on the same connected interface, after the new level has held for
/// `stabilityWindow`, and no sooner than `cooldown` after the last delivered one.
/// Time is always injected so the rules are deterministic in tests.
struct LinkQualityNotifier {

    struct Baseline: Equatable {
        var quality: LinkQuality
        var interface: NetworkInterfaceType
    }

    struct Candidate: Equatable {
        var quality: LinkQuality
        var since: Date
    }

    let stabilityWindow: TimeInterval
    let cooldown: TimeInterval

    private(set) var baseline: Baseline?
    private(set) var candidate: Candidate?
    private(set) var lastNotifiedAt: Date?

    init(stabilityWindow: TimeInterval = 30, cooldown: TimeInterval = 300) {
        self.stabilityWindow = stabilityWindow
        self.cooldown = cooldown
    }

    var nextDeadline: Date? {
        guard let candidate else { return nil }
        let stableAt = candidate.since.addingTimeInterval(stabilityWindow)
        guard let lastNotifiedAt else { return stableAt }
        return max(stableAt, lastNotifiedAt.addingTimeInterval(cooldown))
    }

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

    /// Kept separate from `evaluate` so a change filtered out by the user's behavior
    /// setting updates the baseline without consuming the cooldown.
    mutating func recordDelivery(at date: Date) {
        lastNotifiedAt = date
    }

    mutating func reset() {
        baseline = nil
        candidate = nil
        lastNotifiedAt = nil
    }

    private mutating func clearConnectionState(reason: String) {
        guard baseline != nil || candidate != nil else { return }
        baseline = nil
        candidate = nil
        Logger.notifications.debug("Quality baseline reset: \(reason, privacy: .public)")
    }
}
```

- [x] **Step 5: Run `LinkQualityNotifierTests`** — expected: all pass. Fix the implementation (not the tests) for any failure, unless the test contradicts the spec.

---

### Task 2: Wire the notifier into `NotificationsManager`

**Files:** Modify `QuickNetStats/Managers/NotificationsManager.swift`, `QuickNetStatsTests/NotificationsManagerTests.swift`.

**Interfaces — Consumes:** Task 1 API. **Produces:**
```swift
// NotificationsManager
var now: () -> Date                                  // test seam, default Date.init
var linkQualityBaseline: LinkQualityNotifier.Baseline? { get }
func primeLinkQuality(_ stats: NetworkStats)
func evaluateLinkQuality()                           // internal for tests
func resetLinkQualityTracking()                      // cancels qualityTask + resets notifier
```

- [x] **Step 1: Write failing tests.** In `NotificationsManagerSettleTests` (`QuickNetStatsTests/NotificationsManagerTests.swift`):
  - extend `configureManager` to also set `manager.now = { Date() }` and call `manager.resetLinkQualityTracking()`;
  - extend `restore` to call `manager.resetLinkQualityTracking()` and `manager.now = Date.init`;
  - add the tests below. A `Clock` helper class holds the fake time.

```swift
        private final class FakeClock {
            var current = Date(timeIntervalSinceReferenceDate: 0)
            func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
        }

        @Test("A disconnect with .connects behavior delivers nothing")
        func disconnectWithConnectsBehaviorDeliversNothing() async {
            let manager = NotificationsManager.shared
            let defaults = configureManager(manager)
            defaults.set(InternetNotificationBehavior.connects.rawValue,
                         forKey: Settings.UserDefaultsKeys.notifyInternetBehavior)
            defer { restore(manager) }

            manager.checkForNotifications(
                oldStats: NetworkStats.mockGoodWifiConnection,
                newStats: NetworkStats.mockDisconnected
            )
            try? await Task.sleep(for: .seconds(2))

            #expect(manager.lastDeliveredNotification == nil)
        }

        @Test("A sustained quality drop delivers one notification after the stability window")
        func sustainedQualityDropDelivers() {
            let manager = NotificationsManager.shared
            _ = configureManager(manager)
            defer { restore(manager) }
            let clock = FakeClock()
            manager.now = { clock.current }

            manager.primeLinkQuality(NetworkStats.mockGoodWifiConnection)
            manager.checkForNotifications(
                oldStats: NetworkStats.mockGoodWifiConnection,
                newStats: NetworkStats.mockModerateWifiConnection
            )
            clock.advance(10)
            manager.evaluateLinkQuality()
            #expect(manager.lastDeliveredNotification == nil)

            clock.advance(21)
            manager.evaluateLinkQuality()
            #expect(manager.lastDeliveredNotification?.title == "Network Quality Worsened")
        }

        @Test("A filtered change updates the baseline without consuming the cooldown")
        func filteredChangeDoesNotConsumeCooldown() {
            let manager = NotificationsManager.shared
            let defaults = configureManager(manager)
            defaults.set(LinkQualityNotificationBehavior.improves.rawValue,
                         forKey: Settings.UserDefaultsKeys.notifyQualityBehavior)
            defer { restore(manager) }
            let clock = FakeClock()
            manager.now = { clock.current }

            manager.primeLinkQuality(NetworkStats.mockGoodWifiConnection)
            manager.checkForNotifications(
                oldStats: NetworkStats.mockGoodWifiConnection,
                newStats: NetworkStats.mockModerateWifiConnection
            )
            clock.advance(31)
            manager.evaluateLinkQuality()
            #expect(manager.lastDeliveredNotification == nil)
            #expect(manager.linkQualityBaseline?.quality == .moderate)

            manager.checkForNotifications(
                oldStats: NetworkStats.mockModerateWifiConnection,
                newStats: NetworkStats.mockGoodWifiConnection
            )
            clock.advance(31)
            manager.evaluateLinkQuality()
            #expect(manager.lastDeliveredNotification?.title == "Network Quality Improved")
        }

        @Test("Disabling notifications resets quality tracking")
        func disabledNotificationsResetTracking() {
            let manager = NotificationsManager.shared
            let defaults = configureManager(manager)
            defer { restore(manager) }

            manager.primeLinkQuality(NetworkStats.mockGoodWifiConnection)
            defaults.set(false, forKey: Settings.UserDefaultsKeys.isNotificationActive)
            manager.checkForNotifications(
                oldStats: NetworkStats.mockGoodWifiConnection,
                newStats: NetworkStats.mockModerateWifiConnection
            )
            #expect(manager.linkQualityBaseline == nil)
        }
```

- [x] **Step 2: Run `NotificationsManagerTests`/`NotificationsManagerSettleTests`** — expected: compile failure (missing `now`, `primeLinkQuality`, …).

- [x] **Step 3: Implement in `NotificationsManager.swift`:**
  - Add stored properties next to `settleTask`:
    ```swift
    private var linkQualityNotifier = LinkQualityNotifier()

    /// Pending wake-up for the next link-quality deadline (stability window or cooldown end).
    private var qualityTask: Task<Void, Never>?

    /// Time source; overridable in tests to drive the stability window and cooldown.
    var now: () -> Date = Date.init

    var linkQualityBaseline: LinkQualityNotifier.Baseline? { linkQualityNotifier.baseline }
    ```
  - Replace the global-enabled guard at the top of `checkForNotifications` with:
    ```swift
    guard self.notificationsGloballyEnabled() else {
        resetLinkQualityTracking()
        return
    }

    linkQualityNotifier.observe(newStats, now: now())
    scheduleQualityEvaluation()
    ```
  - Delete the `checkLinkQualityChanges` block (and its `candidates.append`) from `evaluateSettledState`; update its doc comment to "internet and interface" instead of "all three categories".
  - Add:
    ```swift
    func primeLinkQuality(_ stats: NetworkStats) {
        resetLinkQualityTracking()
        linkQualityNotifier.observe(stats, now: now())
    }

    func resetLinkQualityTracking() {
        qualityTask?.cancel()
        qualityTask = nil
        linkQualityNotifier.reset()
    }

    func evaluateLinkQuality() {
        let evaluatedAt = now()
        if let change = linkQualityNotifier.evaluate(now: evaluatedAt) {
            if let notification = checkLinkQualityChanges(
                oldQuality: change.old.rawValue,
                newQuality: change.new.rawValue,
                defaults: defaults
            ) {
                notify(notification)
                linkQualityNotifier.recordDelivery(at: evaluatedAt)
                Logger.notifications.debug("Quality notification sent: \(change.old.description, privacy: .public) → \(change.new.description, privacy: .public)")
            } else {
                Logger.notifications.debug("Quality change filtered by behavior setting")
            }
        }
        scheduleQualityEvaluation()
    }

    private func scheduleQualityEvaluation() {
        qualityTask?.cancel()
        guard let deadline = linkQualityNotifier.nextDeadline else {
            qualityTask = nil
            return
        }
        let delay = max(0, deadline.timeIntervalSince(now()))
        qualityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.evaluateLinkQuality()
        }
    }
    ```
  - Add `import os` at the top.

- [x] **Step 4: Run `NotificationsManagerTests` + `NotificationsManagerSettleTests`** — expected: all pass, including the pre-existing `checkLinkQualityChanges` and settle tests.

---

### Task 3: Prime on first update + path diagnostics in `NetworkStatsManager`

**Files:** Modify `QuickNetStats/Managers/NetworkStatsManager.swift`, `QuickNetStatsTests/NetworkStatsManagerTests.swift`.

**Interfaces — Consumes:** `NotificationsManager.shared.primeLinkQuality(_:)`, `linkQualityBaseline`, `resetLinkQualityTracking()`, `Logger.network`.

- [x] **Step 1: Write the failing test** in `NetworkStatsManagerTests`:

```swift
        @Test("The first published update primes the link-quality baseline")
        func firstUpdatePrimesLinkQuality() {
            let notifications = NotificationsManager.shared
            notifications.resetLinkQualityTracking()
            defer { notifications.resetLinkQualityTracking() }

            let manager = makeManager()
            manager.lastPathStats = NetworkStats.mockGoodWifiConnection
            manager.applyPollResult(reachable: true)

            #expect(notifications.linkQualityBaseline == .init(quality: .good, interface: .wifi))
        }
```

- [x] **Step 2: Run it** — expected: FAIL (`linkQualityBaseline` is nil).

- [x] **Step 3: Implement.** In `publishStats`, inside the `isFirstUpdate` branch after `netStats = newStats`:
  ```swift
  NotificationsManager.shared.primeLinkQuality(newStats)
  ```
  In `handlePathUpdate`, right after `let pathStats = NetworkStats(path: path)`:
  ```swift
  Logger.network.info("""
      Path update: status=\(String(describing: path.status), privacy: .public) \
      interface=\(pathStats.interfaceType.rawValue, privacy: .public) \
      technology=\(String(describing: pathStats.connectionTechnology), privacy: .public) \
      quality=\(pathStats.linkQuality?.description ?? "n/a", privacy: .public) \
      expensive=\(pathStats.isExpensive, privacy: .public) \
      constrained=\(pathStats.isConstrained, privacy: .public)
      """)
  ```
  Add `import os`.

- [x] **Step 4: Run `NetworkStatsManagerTests`** — expected: all pass.

---

### Task 4: Full verification

- [x] **Step 1: Build** via `BuildProject` — expected: success, no new warnings in touched files.
- [x] **Step 2: Run the full test suite** via `RunAllTests` — expected: all pass. Report any failure verbatim.
- [x] **Step 3: `swiftlint lint`** — expected: no violations in touched files; fix any introduced.
- [x] **Step 4: Confirm `git status`** shows only the intended files changed/added and nothing is committed.
