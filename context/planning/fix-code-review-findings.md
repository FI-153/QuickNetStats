# Plan: Fix Code-Review Findings (Updates & Improvements)

> **Date**: 2026-07-03
> **Scope**: All findings from the "what can be updated or made better" review — 5 high-impact bugs, 6 medium issues, cosmetic/low items, and macOS-13-compatible modernization. Efficiency-only findings (15 s reachability poll redesign) are out of scope.
> **Prerequisite**: None. Work happens on branch `fix/code-review-findings` (branched from `develop`).

> **For agentic workers:** Execute this plan task-by-task with strict TDD (red → green per step). Steps use checkbox (`- [ ]`) syntax; check each box immediately upon completing it. Do NOT commit or push — leave all changes uncommitted on the branch.

---

## Context

A three-way code review (improvements / structure / efficiency) found that the app is structurally sound but ships several user-visible bugs: the update checker can never report an update, the "Use Animations" toggle is wired to the wrong setting, the Reduce Motion default is inverted, a failed reachability probe leaves the app stuck on "No Connection" forever, and dark mode renders black-on-dark icons in non-colorful mode. Release tooling uploads an un-stapled zip. Test coverage misses exactly the code paths that broke.

---

## Overview

```
UpdateManager ──(1 regex + status check + injectable session)──> testable, correct updates
AboutView ─────(render errorMessage)────────────────────────────> visible failures
Settings ──────(!reduceMotion default) + VisualsView (binding)──> animations controllable
NotificationsManager ──(async APIs, Task settle timer, seams)──> testable, modern
NetworkStatsManager ──(keep polling while path satisfied)──────> recovers from dead router
NetStatsView ──(colorScheme in the View, not the class)────────> dark mode readable
NetworkDetailsManager ──(short-timeout session, IFF flags)─────> robust IP fetch
release.sh ──(re-zip after staple, trap cleanup)───────────────> stapled artifact shipped
Cleanup sweep ──(renames, dead code, typos, pbxproj target)────> hygiene
```

## Global Constraints

- Deployment target stays **macOS 13.0** — no `@Observable`, no macOS-14-only API.
- No new dependencies. Swift Testing (`import Testing`) for all tests.
- Project has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- Follow `context/styling/formatting.md`. `swiftlint lint` must pass at the end.
- **Never run `git commit`, `git add`, or `git push`.** Stay on branch `fix/code-review-findings`.
- The intentional "Camponents" directory spelling stays.
- Tasks 1–9 use the **current** identifier names (e.g. `mockGoodWifiCoonection`); Task 10 renames them globally, including in code added by earlier tasks.

### Build / test commands

Xcode 26.5 is open with this project as tab `windowtab1`; use its MCP service via the helper:

```bash
# Build
python3 /Users/federicoimberti/.claude/jobs/6e62f175/tmp/xcode_mcp.py call BuildProject '{"tabIdentifier":"windowtab1"}'
# Run the full test suite
python3 /Users/federicoimberti/.claude/jobs/6e62f175/tmp/xcode_mcp.py call RunAllTests '{"tabIdentifier":"windowtab1"}'
# Fetch build log on failure
python3 /Users/federicoimberti/.claude/jobs/6e62f175/tmp/xcode_mcp.py call GetBuildLog '{"tabIdentifier":"windowtab1"}'
```

CLI fallback if the bridge misbehaves (`xcode-select` points at CommandLineTools, so `DEVELOPER_DIR` is required):

```bash
env DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer \
  xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'
```

---

## Design

### 1. UpdateManager (`QuickNetStats/Managers/UpdateManager.swift`)

Three defects: (a) `replacingOccurrences(of: "[vV]", ...)` turns tag `V.2.3.0` into `.2.3.0` — leading dot kept — and `".2.3.0".compare("2.2.0", .numeric)` is ascending, so `isUpdateAvailable` is always false; (b) HTTP status is never checked, so a GitHub 403 surfaces as a decode error; (c) `URLSession.shared` is hard-coded and `init` is private, making it untestable.

Changes:
- `private init() {}` → `init(session: URLSession = .shared)` storing `private let session: URLSession`. `static let shared = UpdateManager()` keeps working; tests build their own instances (fresh `lastCheck = .distantPast` also sidesteps the cooldown).
- New internal static helper, mirror of the regex `release.sh` already uses:
  ```swift
  /// Strips a leading "v"/"V" and optional dot from a release tag (e.g. "V.2.3.0" -> "2.3.0").
  static func cleanVersion(fromTag tag: String) -> String {
      tag.replacingOccurrences(of: "^[vV]\\.?", with: "", options: .regularExpression)
  }
  ```
- `isVersion(_:newerThan:)` becomes internal (drop `private`) so it's directly testable.
- `checkForUpdates()` validates the status code and uses `defer` for the bookkeeping:
  ```swift
  self.isLoading = true
  self.errorMessage = nil
  defer {
      self.lastCheck = Date()
      self.isLoading = false
  }

  do {
      let (data, response) = try await session.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode) else {
          self.errorMessage = "GitHub responded with an unexpected status code"
          return
      }

      let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

      let remoteVersion = Self.cleanVersion(fromTag: release.tagName)
      self.latestVersion = remoteVersion
      self.isUpdateAvailable = isVersion(remoteVersion, newerThan: currentVersion)

  } catch {
      print("Update check failed: \(error.localizedDescription)")
      self.errorMessage = error.localizedDescription
  }
  ```

Tests reuse `MockURLProtocol` (already module-visible in `QuickNetStatsTests/InternetReachabilityCheckerTests.swift`).

### 2. AboutView error state (`QuickNetStats/Views/SettingsView/AboutView.swift`)

`errorMessage` is published but never rendered — failures show "You Are Up To Date!". Branch `updatesSection()` on it:

```swift
fileprivate func updatesSection() -> some View {
    VStack(spacing: 8) {
        if let errorMessage = updateManager.errorMessage {
            Image(systemName: "exclamationmark.triangle")
                .resizable()
                .scaledToFit()
                .frame(width: 35)

            Text("Could Not Check for Updates")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            // ... existing icon / "up to date" / version-arrow content unchanged ...
        }
    }
}
```

### 3. Settings default + VisualsView binding

- `QuickNetStats/Models/Settings.swift:47`: `useAnimations` defaults to `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` — inverted. Fix: `!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
- `QuickNetStats/Views/SettingsView/VisualsView.swift:19`: the "Use Animations" toggle binds `settings.$showSummaryInMenu`. Fix: `settings.$useAnimations`.

No automated test for the default: `@AppStorage` reads the real `UserDefaults.standard` of the host app, so a test would have to delete the user's actual stored preference. Verified by build + inspection instead.

### 4. NotificationsManager (`QuickNetStats/Managers/NotificationsManager.swift`)

Modernization (macOS-13-safe) plus the seams needed to write real settle-behavior tests:

- `checkNotificationStatus()` / `requestNotificationPermission()` switch from completion handlers to the async `UNUserNotificationCenter` API inside a `Task { ... }` (signatures stay synchronous — call sites don't change).
- The `DispatchWorkItem` settle timer becomes a cancellable `Task` (`settleTimer: DispatchWorkItem?` → `settleTask: Task<Void, Never>?`), matching the pattern in `NetworkStatsManager`.
- New internal seams:
  - `var defaults: UserDefaults = .standard` — used by `notificationsGloballyEnabled()` and `evaluateSettledState()` instead of the hard-coded `UserDefaults.standard`, so tests stop polluting real preferences.
  - `var lastDeliveredNotification: QuickNetStats.Notification?` — set in `notify(_ notification:)` before scheduling; lets tests assert what the settle window actually delivered.
  - `var suppressSystemNotifications = false` — early-return in `scheduleNotification` when true, so tests never hit `UNUserNotificationCenter` (which can crash or fire real banners in a test run).
- Comment typo fixes in this file: "immediatelly" → "immediately", "permisison" → "permission".

`QuickNetStatsTests/NotificationsManagerTests.swift` settle suite is rewritten: it currently contains **zero `#expect`** and writes to real `UserDefaults.standard`. New version uses an isolated suite via `manager.defaults`, sets `suppressSystemNotifications = true`, and asserts `lastDeliveredNotification` is nil after a blip and non-nil after a genuine change.

### 5. NetworkStatsManager (`QuickNetStats/Managers/NetworkStatsManager.swift`)

Two behavioral bugs and one latent leak:

**Stuck offline (high).** When the path stays `.satisfied` but the probe fails, `handlePathUpdate` publishes offline and *stops polling*; `pollReachability` does the same on failure. No new path event will arrive, so the app shows "No Connection" until manual refresh. Fix: poll for as long as the path is satisfied — regardless of probe outcome — and publish only on transitions:

- New state: `var lastPathStats: NetworkStats?` (internal for tests) — the latest connected snapshot from the path; set in the connected branch of `handlePathUpdate`, cleared in the disconnected branch and in `stopMonitoring()`.
- `handlePathUpdate` connected branch keeps polling alive whatever the probe said:
  ```swift
  lastPathStats = pathStats
  reachabilityTask = Task { [weak self] in
      guard let self else { return }
      let reachable = await self.reachabilityChecker.checkReachability()
      guard !Task.isCancelled else { return }

      self.publishStats(reachable ? pathStats : NetworkStats.defaultOffline)

      // Keep polling while the path is satisfied so recovery is detected
      // even when the probe failed (e.g. the router lost upstream).
      self.startPolling()
  }
  ```
- Poll results go through a transition-guarded internal method (also prevents re-publishing identical offline stats every 15 s while the outage lasts):
  ```swift
  private func pollReachability() async {
      let reachable = await reachabilityChecker.checkReachability()
      guard !Task.isCancelled else { return }
      applyPollResult(reachable: reachable)
  }

  /// Publishes stats for a poll result, only on connectivity transitions so
  /// repeated identical results don't re-publish. Internal for testing.
  func applyPollResult(reachable: Bool) {
      guard let pathStats = lastPathStats else { return }

      if reachable && !netStats.isConnected {
          publishStats(pathStats)
      } else if !reachable && netStats.isConnected {
          publishStats(NetworkStats.defaultOffline)
      }
  }
  ```
  `pollReachability` no longer calls `stopPolling()`.

**Spurious "Internet Connected" on refresh (medium).** `refresh()` → `stopMonitoring()` silently resets `netStats` to offline; the next `publishStats` compares offline→connected and notifies although nothing changed. Fix: `refresh()` sets `isFirstUpdate = true` between stop and start, so the first publish after a restart is a baseline. `isFirstUpdate` becomes internal for the test.

**Latent retain cycle.** `pollingTask` captures `self` strongly in an infinite loop, so `deinit` can never run while polling. Fix:
```swift
pollingTask = Task { [weak self] in
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(15))
        guard !Task.isCancelled, let self else { break }
        await self.pollReachability()
    }
}
```

**Testability.** `init` gains `autoStart: Bool = true`; tests pass `false` so no real `NWPathMonitor` starts. New file `QuickNetStatsTests/NetworkStatsManagerTests.swift` with a `MockReachabilityChecker` covers the recovery transition (the regression that matters), the no-republish guard, and the refresh flag reset. Tests set `NotificationsManager.shared.suppressSystemNotifications = true` and point `NotificationsManager.shared.defaults` at a throwaway suite (Task 4's seams — hence the ordering).

### 6. NetStatsView dark mode (`Views/NetStatsView/`)

`@Environment(\.colorScheme)` in the plain class `NetStatsViewModel` never resolves (always `.light`), so non-colorful mode picks `.black` icons in dark mode. Fix: delete the property and `isDarkModeEnabled` from the view model; read the scheme in the View, where it works:

```swift
// NetStatsView
@Environment(\.colorScheme) private var colorScheme

private var monochromeColor: Color {
    colorScheme == .dark ? .secondary : .black
}
```

Both usages become `settings.isColorful ? vm.linkQualityColor : monochromeColor`. (Preserves the original design intent — `.secondary` in dark, `.black` in light — rather than switching to `.primary`.) `NetStatsViewModelTests` doesn't reference `isDarkModeEnabled`, so no test changes.

### 7. NotificationView (`Views/SettingsView/NotificationView.swift`)

The view reads `NotificationsManager.shared.areNotificationsEnabled` without observing it (banner goes stale) and calls `checkNotificationStatus()` in `init` (side effect on every parent re-render). Fix, following the pattern `AboutView` already uses:

```swift
struct NotificationView: View {
    @ObservedObject var settings: Settings
    @ObservedObject private var notificationsManager = NotificationsManager.shared
    // custom init deleted entirely

    var body: some View {
        Form {
            if !notificationsManager.areNotificationsEnabled { ... }
            ...
        }
        .formStyle(.grouped)
        .padding()
        .task {
            notificationsManager.checkNotificationStatus()
        }
    }
}
```
The two `NotificationsManager.shared.` calls inside `.onChange` become `notificationsManager.`.

### 8. NetworkDetailsManager (`Managers/NetworkDetailsManager.swift`)

- The ipify fetch uses `URLSession.shared` (60 s default timeout). Fix: `init(session: URLSession = .reachabilitySession)` — reuses the existing 5 s-timeout ephemeral session and makes the manager testable. Store `private let session: URLSession`; `fetchPublicIpAddress` uses it.
- `getPrivateIPAddress()` returns the first `en*` IPv4 even from an inactive interface. Add an interface-flags guard inside the loop, before the family check:
  ```swift
  let flags = Int32(interface.ifa_flags)
  guard (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0 else { continue }
  ```
- New `QuickNetStatsTests/NetworkDetailsManagerTests.swift` using `MockURLProtocol`: 200 → `publicIP` set; 500 → `publicIP` nil.
- Skipped: cancelling a prior in-flight fetch. With a 5 s timeout the stale-write window is negligible for a value that changes rarely; add cancellation if it ever bites.

### 9. release.sh staple order (`scripts/release.sh`)

The zip is created (step 3) before stapling (step 5) and that pre-staple zip is uploaded — Homebrew users get an app whose Gatekeeper check requires a network lookup. Fix: re-zip after stapling, and make cleanup crash-safe with a `trap`:

- After the `cleanup()` definition add: `trap cleanup EXIT` and delete the explicit `cleanup` call at the end of the script.
- Insert after step 5 (staple), before tagging:
  ```bash
  # ─── Step 5b: Re-zip stapled app ────────────────────────────────────────────
  info "Re-creating zip with stapled app..."
  rm -f "$PROJECT_DIR/$ZIP_NAME"
  cd "$EXPORT_DIR"
  zip -r -q "$PROJECT_DIR/$ZIP_NAME" "$APP_NAME.app"
  cd "$PROJECT_DIR"
  green "Zip updated with stapled app"
  ```
- Skipped: re-run recovery when the tag exists but the release step failed — rare, recoverable by hand.

### 10. Cleanup sweep (multiple files)

All mechanical; grouped because each is a rename/deletion verified by the same build+test run:

| Change | Where |
|---|---|
| `exit(0)` → `NSApp.terminate(nil)` | `Views/SettingsView/SettingsView.swift:46` |
| Delete `import Playgrounds` + `#Playground {}` blocks | `NetworkStatsManager.swift`, `NetworkDetailsManager.swift`, `UpdateManager.swift` (tails of each file) |
| Class `Notification` → `AppNotification`; file `git mv` to `AppNotification.swift`; drop the now-unneeded `QuickNetStats.Notification` qualifications; make `==` consistent with `<` (compare `priority`, `created`, `title` instead of `id`) | `Models/Notification.swift`, `NotificationsManager.swift`, `NotificationTests.swift`, seams added in Task 4/5 tests |
| Delete dead `linkQualityDescription` (property + all assignments) | `Models/NetworkStats.swift:66,158,161,164,167` |
| `Coonection` → `Connection`, `mockExpansiveCellCoonection` → `mockExpensiveCellConnection` | `NetworkStats.swift`, `NetStatsView.swift`, `NotificationsManagerTests.swift`, `NetStatsViewModelTests.swift`, `NetworkStatsTests.swift`, new tests from Tasks 4/5, `CLAUDE.md` (mentions `mockGoodWifiCoonection`) |
| `netIntervaceType` → `netInterfaceType` | `Views/Camponents/NetworkInterfaceView.swift` (all), `NetStatsView.swift:26` |
| Class `LaunchAtLoginManager` → `StartAtLoginManager` (matches file name + CLAUDE.md) | `Managers/StartAtLoginManager.swift:12`, `Views/SettingsView/MenuBarView.swift:13` |
| Stale header comments → actual file names | `NetworkStatsManager.swift:2`, `NetStatsView.swift:2`, `Views/Modifiers/ShimmerEffect.swift:2`, `Views/Camponents/FooterButtonLabelView.swift:2` |
| Project-level `MACOSX_DEPLOYMENT_TARGET = 26.0` → `13.0` (2 occurrences, project-level configs only; target-level 13.0 entries stay) | `QuickNetStats.xcodeproj/project.pbxproj:297,357` |

If a `NotificationTests` assertion depends on the old UUID-based `==`, update it to the new content-based semantics — the `<` ordering tests must stay green unchanged.

---

## Edge Cases & Constraints

- **Beta tags**: `cleanVersion(fromTag: "V.2.2.0-Beta-2")` → `"2.2.0-Beta-2"`, and numeric comparison ranks it above `"2.2.0"`. That means a beta pre-release could be offered over a stable of the same base version — pre-existing behavior, unchanged by this plan; noted, not fixed.
- **`applyPollResult` before any path update**: `lastPathStats` is nil → early return, no publish. Correct: polling only ever starts after a connected path update.
- **Concurrent path update + in-flight poll probe**: `handlePathUpdate` cancels `reachabilityTask` but an in-flight poll probe can still land; `applyPollResult`'s transition guard makes a stale result at worst a one-cycle glitch corrected by the next poll tick.
- **`Task.sleep(for:)` and `Duration`** are macOS 13+ — already used by the existing code, safe.
- **Tests touching singletons** (`NotificationsManager.shared`): suites that mutate `defaults` / `suppressSystemNotifications` must restore state (defer) and stay `.serialized` to avoid cross-suite interference.
- **`getifaddrs` flags check** could in principle exclude an interface mid-DHCP; the fetch re-runs on every popover open, so a transiently missing private IP self-heals.

---

## Implementation Checklist

> TDD discipline per task: write the failing test, run it and see it fail, implement, run and see it pass. Verification runs through the Xcode MCP helper (see Global Constraints). No commits.

### Task 1: UpdateManager correctness + testability

- [x] **1.1** Create `QuickNetStatsTests/UpdateManagerTests.swift` with failing tests:

```swift
//
//  UpdateManagerTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

@Suite("UpdateManager", .serialized)
struct UpdateManagerTests {

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - Version tag cleaning

    @Test(
        "cleanVersion strips tag prefixes",
        arguments: [
            ("V.2.3.0", "2.3.0"),
            ("v2.3.0", "2.3.0"),
            ("V2.3.0", "2.3.0"),
            ("2.3.0", "2.3.0"),
            ("V.2.2.0-Beta-1", "2.2.0-Beta-1"),
        ]
    )
    func cleanVersionStripsPrefixes(tag: String, expected: String) {
        #expect(UpdateManager.cleanVersion(fromTag: tag) == expected)
    }

    // MARK: - Version comparison

    @Test("isVersion detects a newer remote version")
    func newerRemoteDetected() {
        let manager = UpdateManager(session: mockSession())
        #expect(manager.isVersion("2.3.0", newerThan: "2.2.0"))
        #expect(!manager.isVersion("2.2.0", newerThan: "2.2.0"))
        #expect(!manager.isVersion("2.1.9", newerThan: "2.2.0"))
    }

    // MARK: - checkForUpdates

    @Test("A newer release tag flags an update")
    func updateAvailableFromRelease() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let body = #"{"tag_name": "V.99.0.0", "html_url": "https://example.com"}"#
            return (response, Data(body.utf8))
        }

        let manager = UpdateManager(session: mockSession())
        await manager.checkForUpdates()

        #expect(manager.isUpdateAvailable)
        #expect(manager.latestVersion == "99.0.0")
        #expect(manager.errorMessage == nil)
    }

    @Test("A non-2xx response surfaces an error, not 'up to date'")
    func httpErrorSurfaced() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 403,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let manager = UpdateManager(session: mockSession())
        await manager.checkForUpdates()

        #expect(manager.errorMessage != nil)
        #expect(!manager.isUpdateAvailable)
        #expect(!manager.isLoading)
    }
}
```

- [x] **1.2** Run the suite — expect compile failure (`cleanVersion` and `init(session:)` don't exist; `isVersion` is private).
- [x] **1.3** Implement in `QuickNetStats/Managers/UpdateManager.swift`: replace `private init() {}` with `init(session: URLSession = .shared)` + stored `private let session`; add `static func cleanVersion(fromTag:)`; drop `private` from `isVersion`; rewrite the body of `checkForUpdates()` per the Design section (status-code guard, `defer` bookkeeping, `session` instead of `URLSession.shared`, `Self.cleanVersion(fromTag:)` instead of the broken regex).
- [x] **1.4** Run the full test suite — expect all green. (DEVIATION: adding a 2nd `MockURLProtocol`-using suite exposed cross-suite handler contamination — Swift Testing runs suites in parallel, so `.serialized` alone is insufficient. Isolated per-session via a token header + `handlers` dict in `MockURLProtocol`; `mockSession()` in both `UpdateManagerTests` and `InternetReachabilityCheckerTests` snapshots the current handler into a token-keyed slot. All plan test bodies stay verbatim.)

### Task 2: AboutView renders update-check failures

- [x] **2.1** Rewrite `updatesSection()` in `QuickNetStats/Views/SettingsView/AboutView.swift` per the Design section (error branch first, existing content in `else`).
- [x] **2.2** Build — expect success. (View-only change; no unit test target for views.)

### Task 3: Animations toggle + Reduce Motion default

- [x] **3.1** `QuickNetStats/Views/SettingsView/VisualsView.swift:19`: change `variable: settings.$showSummaryInMenu` → `variable: settings.$useAnimations`.
- [x] **3.2** `QuickNetStats/Models/Settings.swift:47`: change default to `!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
- [x] **3.3** Build + run full suite — expect green (no automated test: it would require mutating the developer's real preferences; see Design).

### Task 4: NotificationsManager modernization + settle-test rewrite

- [x] **4.1** Replace the settle suite in `QuickNetStatsTests/NotificationsManagerTests.swift` with failing tests:

```swift
@Suite("NotificationsManager Settle Behavior", .serialized)
struct NotificationsManagerSettleTests {

    /// Configures the shared manager with an isolated defaults suite and
    /// suppressed system notifications. Returns the suite for cleanup.
    private func configureManager(_ manager: NotificationsManager) -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: Settings.UserDefaultsKeys.isNotificationActive)
        defaults.set(InternetNotificationBehavior.changes.rawValue,
                     forKey: Settings.UserDefaultsKeys.notifyInternetBehavior)
        manager.defaults = defaults
        manager.suppressSystemNotifications = true
        manager.lastDeliveredNotification = nil
        return defaults
    }

    private func restore(_ manager: NotificationsManager) {
        manager.defaults = .standard
        manager.suppressSystemNotifications = false
        manager.lastDeliveredNotification = nil
    }

    @Test("A blip that settles back to the original state delivers nothing")
    func blipProducesNoNotification() async {
        let manager = NotificationsManager.shared
        _ = configureManager(manager)
        defer { restore(manager) }

        let connected = NetworkStats.mockGoodWifiCoonection
        let disconnected = NetworkStats.mockDisconnected

        // Blip: connected -> disconnected -> connected within the settle window
        manager.checkForNotifications(oldStats: connected, newStats: disconnected)
        manager.checkForNotifications(oldStats: disconnected, newStats: connected)

        try? await Task.sleep(for: .seconds(2))

        #expect(manager.lastDeliveredNotification == nil)
    }

    @Test("A genuine disconnect that persists past the settle window delivers")
    func realChangeDelivers() async {
        let manager = NotificationsManager.shared
        _ = configureManager(manager)
        defer { restore(manager) }

        manager.checkForNotifications(
            oldStats: NetworkStats.mockGoodWifiCoonection,
            newStats: NetworkStats.mockDisconnected
        )

        try? await Task.sleep(for: .seconds(2))

        #expect(manager.lastDeliveredNotification?.title == "Internet Disconnected")
    }
}
```

- [x] **4.2** Run — expect compile failure (`defaults`, `suppressSystemNotifications`, `lastDeliveredNotification` don't exist).
- [x] **4.3** Implement in `QuickNetStats/Managers/NotificationsManager.swift`:
  - Add the three internal seams from the Design section; route `notificationsGloballyEnabled()` and `evaluateSettledState()` through `self.defaults`; set `lastDeliveredNotification = notification` in `notify(_ notification:)`; guard `scheduleNotification` with `guard !suppressSystemNotifications else { return }`.
  - Convert `checkNotificationStatus` / `requestNotificationPermission` to the async `UNUserNotificationCenter` API inside `Task { ... }` (Design section), keeping signatures synchronous.
  - Replace `settleTimer: DispatchWorkItem?` with `settleTask: Task<Void, Never>?`:
    ```swift
    settleTask?.cancel()
    settleTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(self?.settleDelay ?? 1.0))
        guard !Task.isCancelled else { return }
        self?.evaluateSettledState()
    }
    ```
    (and `settleTask = nil` where `settleTimer = nil` was.)
  - Fix "immediatelly" → "immediately" and "permisison" → "permission" in comments.
- [x] **4.4** Run the full test suite — expect green (including the pre-existing check-method suite).

### Task 5: NetworkStatsManager recovery + refresh + retain cycle

- [x] **5.1** Create `QuickNetStatsTests/NetworkStatsManagerTests.swift` with failing tests:

```swift
//
//  NetworkStatsManagerTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

final class MockReachabilityChecker: InternetReachabilityChecking {
    var result: Bool
    init(result: Bool) { self.result = result }
    func checkReachability() async -> Bool { result }
}

@Suite("NetworkStatsManager", .serialized)
struct NetworkStatsManagerTests {

    private func makeManager() -> NetworkStatsManager {
        NotificationsManager.shared.suppressSystemNotifications = true
        return NetworkStatsManager(
            reachabilityChecker: MockReachabilityChecker(result: true),
            autoStart: false
        )
    }

    @Test("A successful poll after a failed one restores the connection stats")
    func pollRecoveryAfterFailure() {
        let manager = makeManager()
        manager.lastPathStats = NetworkStats.mockGoodWifiCoonection

        manager.applyPollResult(reachable: true)
        #expect(manager.netStats.isConnected)

        manager.applyPollResult(reachable: false)
        #expect(!manager.netStats.isConnected)

        // Regression: polling used to stop after a failure, leaving the app
        // offline forever even when connectivity returned.
        manager.applyPollResult(reachable: true)
        #expect(manager.netStats.isConnected)
        #expect(manager.netStats.interfaceType == .wifi)
    }

    @Test("A failed poll while already offline publishes nothing new")
    func repeatedFailureStaysQuiet() {
        let manager = makeManager()
        manager.lastPathStats = NetworkStats.mockGoodWifiCoonection

        manager.applyPollResult(reachable: false)
        #expect(!manager.netStats.isConnected)

        manager.applyPollResult(reachable: false)
        #expect(!manager.netStats.isConnected)
    }

    @Test("A poll result with no known path stats is ignored")
    func pollWithoutPathStatsIsIgnored() {
        let manager = makeManager()
        manager.applyPollResult(reachable: true)
        #expect(!manager.netStats.isConnected)
    }

    @Test("Refresh resets the first-update flag so no spurious notification fires")
    func refreshResetsFirstUpdateFlag() {
        let manager = makeManager()
        manager.isFirstUpdate = false

        manager.refresh()

        #expect(manager.isFirstUpdate)
    }
}
```

- [x] **5.2** Run — expect compile failure (`autoStart:`, `lastPathStats`, `applyPollResult`, internal `isFirstUpdate` don't exist).
- [x] **5.3** Implement in `QuickNetStats/Managers/NetworkStatsManager.swift` per the Design section:
  - `init(reachabilityChecker: InternetReachabilityChecking = InternetReachabilityChecker(), autoStart: Bool = true)`; wrap the `startMonitoring()` call in `if autoStart`.
  - `private var isFirstUpdate` → `var isFirstUpdate` (internal).
  - Add `var lastPathStats: NetworkStats?`; set/clear it in `handlePathUpdate` (connected/disconnected branches) and clear in `stopMonitoring()`.
  - Rework the `handlePathUpdate` connected branch (weak-self task, publish reachable-or-offline, **always** `startPolling()`).
  - Add `applyPollResult(reachable:)`; `pollReachability` calls it and no longer stops polling.
  - `refresh()` sets `isFirstUpdate = true` between `stopMonitoring()` and `startMonitoring()`.
  - `[weak self]` in the `pollingTask` closure.
- [x] **5.4** Run the full test suite — expect green.

### Task 6: Dark-mode monochrome color

- [x] **6.1** `QuickNetStats/Views/NetStatsView/NetStatsViewModel.swift`: delete the `@Environment(\.colorScheme)` property and `isDarkModeEnabled`.
- [x] **6.2** `QuickNetStats/Views/NetStatsView/NetStatsView.swift`: add `@Environment(\.colorScheme) private var colorScheme` and the `monochromeColor` computed property (Design section); replace both `vm.isDarkModeEnabled ? .secondary : .black` expressions with `monochromeColor`.
- [x] **6.3** Build + run full suite — expect green.

### Task 7: NotificationView observes the manager

- [x] **7.1** Rewrite `QuickNetStats/Views/SettingsView/NotificationView.swift` per the Design section: add `@ObservedObject private var notificationsManager = NotificationsManager.shared`, delete the custom `init`, reference `notificationsManager` in `body`/`.onChange`, move the status check into `.task`.
- [x] **7.2** Build — expect success.

### Task 8: NetworkDetailsManager session + interface flags

- [x] **8.1** Create `QuickNetStatsTests/NetworkDetailsManagerTests.swift` with failing tests:

```swift
//
//  NetworkDetailsManagerTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

@Suite("NetworkDetailsManager", .serialized)
struct NetworkDetailsManagerTests {

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("A successful ipify response populates publicIP")
    func publicIPFetched() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data("93.45.10.2".utf8))
        }

        let manager = NetworkDetailsManager(session: mockSession())
        await manager.getAddresses()

        #expect(manager.publicIP == "93.45.10.2")
    }

    @Test("A server error leaves publicIP nil")
    func publicIPNilOnServerError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let manager = NetworkDetailsManager(session: mockSession())
        await manager.getAddresses()

        #expect(manager.publicIP == nil)
    }
}
```

- [x] **8.2** Run — expect compile failure (`init(session:)` doesn't exist).
- [x] **8.3** Implement in `QuickNetStats/Managers/NetworkDetailsManager.swift`: add `init(session: URLSession = .reachabilitySession)` + stored `private let session`; use it in `fetchPublicIpAddress()`; add the `IFF_UP | IFF_RUNNING` guard in `getPrivateIPAddress()` (Design section). (DEVIATION: `mockSession()` uses the token-isolation pattern from Task 1's deviation, not the plain version in the plan snippet, so this suite runs in parallel with the other `MockURLProtocol` suites deterministically. Test bodies verbatim.)
- [x] **8.4** Run the full test suite — expect green.

### Task 9: release.sh staple order

- [x] **9.1** Edit `scripts/release.sh`: add `trap cleanup EXIT` after the `cleanup()` definition; insert Step 5b (re-zip after staple, Design section) between stapling and tagging; remove the explicit `cleanup` call at the end.
- [x] **9.2** Verify: `bash -n scripts/release.sh` — expect no output, exit 0.

### Task 10: Cleanup sweep

- [x] **10.1** Apply every row of the cleanup table in the Design section (renames, dead code, Playground blocks, `exit(0)`, header comments, pbxproj project-level deployment target). Use project-wide search to catch every reference, including in test files added by Tasks 1–8 and in `CLAUDE.md`. (Also updated the header comment inside the renamed `AppNotification.swift` for consistency, and split the old UUID-based `differentUUIDsNotEqual` test into `sameContentIsEqual` + `differentTitleNotEqual` to match the new content-based `==`.)
- [x] **10.2** `swiftlint lint` — expect zero violations. (0 violations across 26 files; required `DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer` since `xcode-select` points at CommandLineTools.)
- [x] **10.3** Build + run the **full** test suite — expect green. (110 tests, all passing.)
- [x] **10.4** Sanity grep: no remaining `Coonection`, `Expansive`, `netIntervaceType`, `LaunchAtLoginManager`, `#Playground`, `exit(0)`, or `linkQualityDescription` anywhere in the repo (excluding this plan file). (DEVIATION: one `mockGoodWifiCoonection` remains at `context/planning/debounce-notifications.md:549` — a completed historical plan not listed in the cleanup table; project convention treats plans as immutable historical records, so it was left as-is. All live code, tests, `CLAUDE.md`, and every other token are clean.)

### Task 11: Independent code review

- [x] **11.1** After Tasks 1–10 are complete and green, a **Fable** subagent (dispatched by the orchestrating session, not the implementation agent) performs a full code review of the uncommitted diff (`git diff develop`) against this plan: correctness of each fix, TDD coverage, regressions, style conformance. Findings are reported back to the user before anything is committed. (Verdict: **safe to commit, no blockers**. Independently re-verified: build OK, 110/110 tests, swiftlint 0 violations. Two should-fix test-infrastructure findings — cross-suite race on the shared `NotificationsManager` singleton between `NetworkStatsManagerTests` and the settle suite, and unsynchronized access to `MockURLProtocol.handlers` — plus five nits; all reported to the user, none product bugs.)
