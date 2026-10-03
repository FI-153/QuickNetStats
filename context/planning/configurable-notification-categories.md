# Plan: Configurable Notification Categories

> **Date**: 2026-10-03
> **Scope**: Let users disable Internet Status and Link Quality notifications individually, alongside the existing Interface Changes toggle
> **Prerequisite**: `fix-link-quality-notification-spam.md` (same branch `fix/link-quality-notifications`; relies on `LinkQualityNotifier` and the filtered-change path)

---

## Context

Notification settings offer a master "Send Notifications" switch plus per-category options, but only
Interface Changes can be turned off (`notifyInterfaceChanges`, default off). Internet Status and Link
Quality only expose a *when* picker (`notifyInternetBehavior`: Connects / Disconnects / Changes;
`notifyQualityBehavior`: Improves / Worsens / Changes). A user who wants, say, only interface-change
notifications has no way to silence the other two.

---

## Overview

```
NotificationView                         Settings (@AppStorage)
 ├─ Interface Changes  [toggle] ───────► notifyInterfaceChanges   (existing, default false)
 ├─ Internet Status    [toggle] ───────► notifyInternetEnabled    (new, default true)
 │    └─ Notify When   [picker] ───────► notifyInternetBehavior   (existing; shown only when on)
 └─ Link Quality       [toggle] ───────► notifyQualityEnabled     (new, default true)
      └─ Notify When   [picker] ───────► notifyQualityBehavior    (existing; shown only when on)

NotificationsManager (reads UserDefaults directly)
 ├─ checkInternetStatusChanges ── nil when notifyInternetEnabled == false
 └─ checkLinkQualityChanges   ── nil when notifyQualityEnabled == false
```

---

## Design

### Settings model

Two new keys in `Settings.UserDefaultsKeys` and matching `@AppStorage` properties:

- `notifyInternetEnabled: Bool = true`
- `notifyQualityEnabled: Bool = true`

Defaults are `true` for both upgrading users and fresh installs, so nobody's current behavior
changes; users only gain the ability to opt out. Existing behavior pickers and
`notifyInterfaceChanges` are unchanged.

### Reading the toggles outside SwiftUI

`@AppStorage`'s default value only applies inside the property wrapper; it is never written to
`UserDefaults`. `NotificationsManager` reads preferences with `defaults.bool(forKey:)`, which returns
`false` for a missing key. Upgrading users have no stored value for the new keys, so a naive read
would silently disable both categories — the opposite of the agreed default.

`NotificationsManager` therefore reads the new keys through a private helper that falls back to
`true` when the key is absent:

```swift
private func isCategoryEnabled(_ key: String, in defaults: UserDefaults) -> Bool {
    defaults.object(forKey: key) as? Bool ?? true
}
```

### Notification logic

- `checkInternetStatusChanges(...)` returns `nil` up front when `notifyInternetEnabled` is off.
- `checkLinkQualityChanges(...)` returns `nil` up front when `notifyQualityEnabled` is off.

Both checks already receive the `defaults` to read from, so the gating lives with the existing
behavior filters and the existing unit-test seam keeps working.

Link-quality tracking (`LinkQualityNotifier`) keeps running when the category is off. A disabled
category flows through the existing "filtered by behavior" path in `evaluateLinkQuality`: the
baseline is promoted but the cooldown is not consumed. Re-enabling the toggle therefore works
immediately with a fresh baseline instead of reporting a stale comparison.

The 1s settle window, candidate priority ordering, and interface-change logic are unchanged.

### UI

`NotificationView`'s "Notifications Settings" section becomes:

- **Interface Changes** — toggle (existing binding, label shortened).
- **Internet Status** — toggle; when on, the "Notify When" picker (Connects / Disconnects /
  Changes) appears beneath it.
- **Link Quality** — toggle; when on, the "Notify When" picker (Improves / Worsens / Changes)
  appears beneath it.

Pickers are conditionally shown (not merely disabled). Reuse `ToggleView` and `PickerView`. No
other layout changes.

### Testing

- `SettingsDefaultsTests`: both new properties default to `true` when the key is absent
  (same save/remove/restore pattern as the existing default tests).
- `NotificationsManagerCheckTests`:
  - internet disabled → `nil` for every `InternetNotificationBehavior` on a real transition;
  - quality disabled → `nil` for a real change;
  - missing keys → treated as enabled (existing tests' `testDefaults` never sets them, so they
    double as regression coverage once the helper parameters default to "unset").
- `NotificationsManagerSettleTests`: quality disabled → sustained change delivers nothing, baseline
  still advances, and re-enabling then notifies on the next sustained change without waiting for a
  cooldown.

---

## Edge Cases & Constraints

- **Upgrade with no stored keys**: treated as enabled via the helper; covered by tests.
- **Master switch off**: all categories silent as today; category toggles stay editable (disabling
  them while the master is off is out of scope).
- **Category off during a pending quality candidate**: the candidate still matures and promotes the
  baseline silently; no notification, no cooldown.
- **All three categories off with master on**: no notifications at all; acceptable, no warning UI.
- **Notification text** unchanged.

---

## Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILLS: superpowers:executing-plans (inline),
> superpowers:test-driven-development, `swift-testing-expert:swift-testing-expert` before writing
> tests and `swiftui-expert:swiftui-expert-skill` before editing the view (if available). Check each
> box (`- [x]`) immediately after completing it. **Never commit, stage, push, or stash.**
> Build/test via Xcode MCP (`mcp__xcode__*`) if it works; otherwise
> `caffeinate -dims env DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'`.
> Lint with `DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer swiftlint lint`.

**Goal:** Internet Status and Link Quality notifications can each be turned off; defaults keep
current behavior.

**Architecture:** Two new `@AppStorage` Bools (default `true`); `NotificationsManager` gates the two
check functions on them via a missing-key-means-true helper; `NotificationView` adds toggles and
shows each picker only when its toggle is on.

**Tech Stack:** Swift 5.9, SwiftUI (`Form`, `.formStyle(.grouped)`), Swift Testing.
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; file-system-synchronized groups.

**Spec:** this file (sections above).

### Global Constraints

- Keys: `notifyInternetEnabled`, `notifyQualityEnabled`; both default `true`.
- A missing key must read as `true` in `NotificationsManager`.
- macOS 13 APIs only in the view (`onChange(of:)` single-param form as already used).
- New methods/properties get docstrings per `context/styling/formatting.md`; no other comments
  unless the *why* is non-obvious.
- `swiftlint lint` clean.

### Review Focus

- Upgrading user with no stored keys still receives internet/quality notifications. Pinned in
  Task 2 (`missingKeysTreatedAsEnabled`).
- Quality disabled must not consume the cooldown. Pinned in Task 2
  (`disabledQualityDoesNotConsumeCooldown`).
- Picker hidden when its toggle is off, without losing the stored behavior value. Covered by design
  (picker binding untouched); verify manually via preview.

### File Map

- Modify: `QuickNetStats/Models/Settings.swift` — keys + properties.
- Modify: `QuickNetStats/Managers/NotificationsManager.swift` — helper + gating.
- Modify: `QuickNetStats/Views/SettingsView/NotificationView.swift` — toggles + conditional pickers.
- Modify: `QuickNetStatsTests/SettingsTests.swift`, `QuickNetStatsTests/NotificationsManagerTests.swift`.

---

### Task 1: Settings keys and defaults

- [x] **Step 1: Write failing tests** in `SettingsDefaultsTests` (`QuickNetStatsTests/SettingsTests.swift`), following the existing pattern:

```swift
    @Test("notifyInternetEnabled defaults to true")
    @MainActor
    func notifyInternetEnabledDefaultsToTrue() {
        let key = Settings.UserDefaultsKeys.notifyInternetEnabled
        let savedValue = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let savedValue {
                UserDefaults.standard.set(savedValue, forKey: key)
            }
        }

        #expect(Settings().notifyInternetEnabled == true)
    }

    @Test("notifyQualityEnabled defaults to true")
    @MainActor
    func notifyQualityEnabledDefaultsToTrue() {
        let key = Settings.UserDefaultsKeys.notifyQualityEnabled
        let savedValue = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let savedValue {
                UserDefaults.standard.set(savedValue, forKey: key)
            }
        }

        #expect(Settings().notifyQualityEnabled == true)
    }
```

- [x] **Step 2: Run `SettingsDefaultsTests`** — expected: compile failure (unknown keys/properties).

- [x] **Step 3: Implement** in `Settings.swift`:
  - In `UserDefaultsKeys`, next to `notifyInterfaceChanges`:
    ```swift
    static let notifyInternetEnabled = "notifyInternetEnabled"
    static let notifyQualityEnabled = "notifyQualityEnabled"
    ```
  - Next to the other notification properties:
    ```swift
    /// Whether internet connect/disconnect notifications are sent. Defaults to on.
    @AppStorage(UserDefaultsKeys.notifyInternetEnabled)
    var notifyInternetEnabled: Bool = true

    /// Whether link-quality notifications are sent. Defaults to on.
    @AppStorage(UserDefaultsKeys.notifyQualityEnabled)
    var notifyQualityEnabled: Bool = true
    ```

- [x] **Step 4: Run `SettingsDefaultsTests`** — expected: pass.

---

### Task 2: Gate the checks in `NotificationsManager`

- [x] **Step 1: Write failing tests.** In `NotificationsManagerCheckTests`, extend `testDefaults` with two optional parameters that are only written when non-nil (so existing tests keep the keys absent):

```swift
    func testDefaults(
        internetBehavior: InternetNotificationBehavior = .connects,
        qualityBehavior: LinkQualityNotificationBehavior = .changes,
        interfaceChanges: Bool = false,
        internetEnabled: Bool? = nil,
        qualityEnabled: Bool? = nil
    ) -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(internetBehavior.rawValue, forKey: Settings.UserDefaultsKeys.notifyInternetBehavior)
        defaults.set(qualityBehavior.rawValue, forKey: Settings.UserDefaultsKeys.notifyQualityBehavior)
        defaults.set(interfaceChanges, forKey: Settings.UserDefaultsKeys.notifyInterfaceChanges)
        if let internetEnabled {
            defaults.set(internetEnabled, forKey: Settings.UserDefaultsKeys.notifyInternetEnabled)
        }
        if let qualityEnabled {
            defaults.set(qualityEnabled, forKey: Settings.UserDefaultsKeys.notifyQualityEnabled)
        }
        return defaults
    }
```

  Add tests:

```swift
    // MARK: - Category toggles

    @Test(
        "Internet notifications are silent when the category is disabled",
        arguments: InternetNotificationBehavior.allCases
    )
    func internetDisabledIsSilent(behavior: InternetNotificationBehavior) {
        let defaults = testDefaults(internetBehavior: behavior, internetEnabled: false)
        let connect = manager.checkInternetStatusChanges(
            wasConnected: false, isConnected: true, newInterface: .wifi, defaults: defaults
        )
        let disconnect = manager.checkInternetStatusChanges(
            wasConnected: true, isConnected: false, newInterface: .none, defaults: defaults
        )
        #expect(connect == nil)
        #expect(disconnect == nil)
    }

    @Test("Quality notifications are silent when the category is disabled")
    func qualityDisabledIsSilent() {
        let defaults = testDefaults(qualityBehavior: .changes, qualityEnabled: false)
        let result = manager.checkLinkQualityChanges(
            oldQuality: LinkQuality.good.rawValue,
            newQuality: LinkQuality.minimal.rawValue,
            defaults: defaults
        )
        #expect(result == nil)
    }

    @Test("Missing category keys are treated as enabled")
    func missingKeysTreatedAsEnabled() {
        let defaults = testDefaults(internetBehavior: .connects, qualityBehavior: .changes)
        #expect(defaults.object(forKey: Settings.UserDefaultsKeys.notifyInternetEnabled) == nil)
        #expect(defaults.object(forKey: Settings.UserDefaultsKeys.notifyQualityEnabled) == nil)

        let internet = manager.checkInternetStatusChanges(
            wasConnected: false, isConnected: true, newInterface: .wifi, defaults: defaults
        )
        let quality = manager.checkLinkQualityChanges(
            oldQuality: LinkQuality.good.rawValue,
            newQuality: LinkQuality.moderate.rawValue,
            defaults: defaults
        )
        #expect(internet?.title == "Internet Connected")
        #expect(quality?.title == "Network Quality Worsened")
    }
```

  In `NotificationsManagerSettleTests` (uses `configureManager`, `restore`, `FakeClock` already in the file):

```swift
        @Test("Disabled quality advances the baseline without consuming the cooldown")
        func disabledQualityDoesNotConsumeCooldown() {
            let manager = NotificationsManager.shared
            let defaults = configureManager(manager)
            defaults.set(false, forKey: Settings.UserDefaultsKeys.notifyQualityEnabled)
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

            defaults.set(true, forKey: Settings.UserDefaultsKeys.notifyQualityEnabled)
            manager.checkForNotifications(
                oldStats: NetworkStats.mockModerateWifiConnection,
                newStats: NetworkStats.mockGoodWifiConnection
            )
            clock.advance(31)
            manager.evaluateLinkQuality()
            #expect(manager.lastDeliveredNotification?.title == "Network Quality Improved")
        }
```

- [x] **Step 2: Run `NotificationsManagerCheckTests` + `NotificationsManagerSettleTests`** — expected: compile failure (unknown keys) or failing assertions once Task 1 exists.

- [x] **Step 3: Implement** in `NotificationsManager.swift`:
  - Add next to `notificationsGloballyEnabled()`:
    ```swift
    /// Reads a per-category toggle, treating a missing key as enabled: `@AppStorage`
    /// defaults are never written to `UserDefaults`, so upgraded installs have no value yet.
    private func isCategoryEnabled(_ key: String, in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
    ```
  - First line of `checkInternetStatusChanges`:
    ```swift
    guard isCategoryEnabled(Settings.UserDefaultsKeys.notifyInternetEnabled, in: defaults) else { return nil }
    ```
  - First line of `checkLinkQualityChanges`:
    ```swift
    guard isCategoryEnabled(Settings.UserDefaultsKeys.notifyQualityEnabled, in: defaults) else { return nil }
    ```

- [x] **Step 4: Run `NotificationsManagerCheckTests` + `NotificationsManagerSettleTests`** — expected: all pass (old and new).

---

### Task 3: Settings UI

- [x] **Step 1: Invoke `swiftui-expert:swiftui-expert-skill`** (if available) and read `NotificationView.swift`, `ToggleView.swift`, `PickerView.swift`.

- [x] **Step 2: Update the "Notifications Settings" section** of `NotificationView.swift` to:

```swift
            Section {

                ToggleView(title: "Interface Changes", variable: settings.$notifyInterfaceChanges)

                ToggleView(title: "Internet Status", variable: settings.$notifyInternetEnabled)

                if settings.notifyInternetEnabled {
                    PickerView(
                        title: "Notify When",
                        selection: $settings.notifyInternetBehavior
                    ) {
                        Text("Connects").tag(InternetNotificationBehavior.connects)
                        Text("Disconnects")
                            .tag(InternetNotificationBehavior.disconnects)
                        Text("Changes").tag(InternetNotificationBehavior.changes)
                    }
                }

                ToggleView(title: "Link Quality", variable: settings.$notifyQualityEnabled)

                if settings.notifyQualityEnabled {
                    PickerView(
                        title: "Notify When",
                        selection: $settings.notifyQualityBehavior
                    ) {
                        Text("Improves")
                            .tag(LinkQualityNotificationBehavior.improves)
                        Text("Worsens")
                            .tag(LinkQualityNotificationBehavior.worsens)
                        Text("Changes").tag(LinkQualityNotificationBehavior.changes)
                    }
                }

            } header: {
                Text("Notifications Settings")
            }
```

  Adjust only if `PickerView`/`ToggleView` signatures differ; keep macOS 13 compatibility.

- [x] **Step 3: Build** and, if the Xcode MCP works, render the `NotificationView` preview (`RenderPreview`) to confirm the layout. If MCP is unavailable, state that the preview was not checked.

---

### Task 4: Full verification

- [x] **Step 1: Build** — expected: success, no new warnings in touched files.
- [x] **Step 2: Run the full test suite** — expected: all pass; report counts and any failure verbatim.
- [x] **Step 3: `swiftlint lint`** — expected: no violations.
- [x] **Step 4: Confirm `git status`** shows only the intended files (plus this plan) changed, nothing staged or committed.
