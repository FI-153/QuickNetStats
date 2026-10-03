# Plan: UI Polish — Copy Feedback, Flexible Layout, Details Expansion

> **Date**: 2026-10-03
> **Scope**: Three highest-impact UI fixes from a SwiftUI review of the popover: (1) visible/announced
> copy-to-clipboard feedback plus labeled icon-only controls, (2) replace rigid frames and hard-coded
> colors and fix the type hierarchy, (3) remove the Connection Details first-frame jump and stop
> reading `NSScreen.main`
> **Prerequisite**: None

---

## Context

A review of the popover UI (`ContentView`, `NetStatsView`, components) with the SwiftUI expert
skill found three areas with the largest user-visible impact:

1. **Silent copy & unlabeled controls.** Clicking an IP (`NetStatsView.ipButtonsSection`) or any
   detail value (`DetailGroupView`) copies to the clipboard with no confirmation; the only hint is a
   hover tooltip. The refresh button (`ContentView.headerButtonsSection`) is an unlabeled icon with
   no tooltip and no in-flight state, so it can be spammed. VoiceOver reads the hero icon and each
   link-quality circle separately. Copy logic is duplicated (`NetStatsViewModel.copyToClipboard`,
   `DetailGroupView.copy`).
2. **Rigid layout & colors.** `AddressView` is a fixed `250×50` with `.title3` text, so longer
   values clip. `LinkQualityView` is forced into `80×80` although its content is larger (it
   overflows its own frame). Monochrome mode hard-codes `.black` in light mode; several places use
   `.gray`/`.foregroundColor` instead of semantic hierarchical styles. Hierarchy is inverted: the
   "Connection Details" disclosure is `.callout`/secondary (least prominent element, gating the most
   content) while group headers inside are `.title2`.
3. **Details expansion jump.** `ConnectionDetailsView.detailsContentHeight` starts at `.infinity`,
   so the first frame after expanding renders the scroll view at the full cap and then shrinks.
   The cap reads `NSScreen.main` (process-global; can be the wrong display) instead of the popover
   window's screen.

Out of scope (deliberately): the `popoverHeight`/chrome subtraction feedback between `ContentView`
and `ConnectionDetailsView`. The chrome is invariant while expanded, so the computation converges;
any transient was not observed, and a structural rewrite is not justified without evidence.

---

## Overview

```
                       ┌──────────────── Clipboard.copy(_:to:) ────────────────┐
                       │  (single copy implementation, returns success Bool)    │
                       └───────────────▲───────────────────────▲──────────────┘
                                       │                       │
 NetStatsView ── CopyButton(value:) ───┘      DetailGroupView ── CopyButton(value:)
   │  label: AddressView(isConfirming:)          label: value Text / "Copied" ✓
   │  hero HStack ── .accessibilityElement(.ignore)
   │                 label = vm.accessibilitySummary(includeSSID:)
   │  monochrome tint = NetStatsViewModel.monochromeColor(for: colorScheme)
   │
   └─ ConnectionDetailsView
        scroll height = detailsScrollHeight(contentHeight: CGFloat?, cap:)   (nil → 0, no jump)
        cap screen    = .onWindowScreenChange { screen = $0 }  (fallback NSScreen.main)

 ContentView refresh button: isRefreshing state → disabled + rotate effect (macOS 15+) + label/help
```

---

## Design

### 1. Copy feedback and labeled controls

**`Clipboard`** — new `QuickNetStats/Managers/Clipboard.swift`:

```swift
enum Clipboard {
    /// Returns false (and leaves the pasteboard untouched) for nil or empty values.
    @discardableResult
    static func copy(_ value: String?, to pasteboard: NSPasteboard = .general) -> Bool
}
```

Replaces `NetStatsViewModel.copyToClipboard(_:)` and `DetailGroupView.copy(_:)` (both removed).
The pasteboard parameter makes it unit-testable with a uniquely named `NSPasteboard`.

**`CopyButton`** — new `QuickNetStats/Views/Camponents/CopyButton.swift`. A plain button that copies
`value`, then shows a confirmation for ~1.2s:

```swift
struct CopyButton<Label: View>: View {
    let value: String?
    var animated: Bool = true
    @ViewBuilder let label: (_ isConfirming: Bool) -> Label
}
```

- State: `@State private var isConfirming = false`, `@State private var confirmationID = 0`.
- Tap → `Clipboard.copy(value)`; on success set `isConfirming = true` (inside
  `withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.15) : nil)`), bump
  `confirmationID`, post a VoiceOver "Copied" announcement.
- `.task(id: confirmationID)` sleeps 1.2s then clears `isConfirming`; re-tapping restarts the timer
  because the id changes (task cancellation handles overlap).
- Reduce motion from `@Environment(\.accessibilityReduceMotion)`; the app's `useAnimations`
  setting is passed in via `animated` (no `Settings` environment dependency, so `DetailGroupView`
  previews stay self-contained).
- Announcement: `AccessibilityNotification.Announcement("Copied").post()` on macOS 14+, fallback
  `NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: "Copied", .priority: NSAccessibilityPriorityLevel.high.rawValue])`.
- `.buttonStyle(.plain)`, `.focusable(false)`, `.help("Click to copy")`,
  `.accessibilityHint("Copies to the clipboard")`. Disabled when `value == nil`.

**`AddressView`** gains `var isConfirming = false`. When confirming, the value text is replaced by
`Label("Copied", systemImage: "checkmark")` (same font/weight). Accessibility:
`.accessibilityElement(children: .ignore)` + `.accessibilityLabel("\(title): \(value)")`.

**`DetailGroupView`** gains `var animated = true` and wraps each value in `CopyButton`, showing
`Label("Copied", systemImage: "checkmark")` while confirming. `ConnectionDetailsView` passes
`settings.useAnimations`.

**Refresh button** (`ContentView`): `@State private var isRefreshing = false`. The action guards
`!isRefreshing`, sets it, runs the existing three refresh calls, clears it with `defer`. Button gets
`.disabled(isRefreshing)`, `.help("Refresh")`, `.accessibilityLabel("Refresh")`. When
`settings.useAnimations` and macOS 15+, the image gets `.symbolEffect(.rotate, isActive: isRefreshing)`;
otherwise the disabled dimming is the feedback.

/new The rotate effect flickered in the running app and was removed. The button stays disabled for
at least 1s (`Task.sleep(until:)` after the refresh calls) so a fast refresh doesn't flash the
disabled state; dimming is the only feedback.

**Hero accessibility** (`NetStatsView`): the icon/quality `HStack` becomes one element:
`.accessibilityElement(children: .ignore)` + `.accessibilityLabel(vm.accessibilitySummary(includeSSID: settings.showNetworkNames))`.

`NetStatsViewModel.accessibilitySummary(includeSSID:) -> String`:
- disconnected → `"Disconnected"`
- otherwise `[interfaceName, ssid?, "link quality <description>"?].joined(", ")` where
  `interfaceName` is `Wi-Fi` / `Ethernet` / `Personal Hotspot` / `Network` (for `.wifi` /
  `.ethernet` / `.cellular` / other), the SSID is included only when `includeSSID && isWifiConnection`
  and non-nil, and the quality clause only when `linkQuality` is non-nil and not `.unknown`.

### 2. Flexible layout, semantic colors, hierarchy

- **`AddressView`**: drop `.frame(width: 250, height: 50)` and the overlay construction. Content
  `HStack` with `.lineLimit(1)` and `.minimumScaleFactor(0.7)`, `.padding(.horizontal, 16)`,
  `.frame(maxWidth: .infinity, minHeight: 50)`, background
  `RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.secondary.opacity(0.3))`.
  In the `HStack(spacing: 16)` of `ipButtonsSection` the two buttons split the width equally
  (≈ the old 250pt each at the 550pt popover width). The label button needs
  `.contentShape(RoundedRectangle(...))` so the whole pill stays clickable.
- **`LinkQualityView`**: remove `.frame(width: 80, height: 80)`; empty circles use
  `.foregroundStyle(.quaternary)`; the "Link Quality" caption uses `.foregroundStyle(.secondary)`.
- **Monochrome tint**: move to `NetStatsViewModel.monochromeColor(for: ColorScheme) -> Color`
  returning `.secondary` for `.dark` and `.primary` for `.light` (was `.black`). `NetStatsView`
  keeps reading `colorScheme` and calls the static.
- **Gray → semantic**: `NetStatsView` SSID text and `NetworkInterfaceView` offline icon use
  `.foregroundStyle(.secondary)` instead of `.gray`/`.foregroundColor(.gray)`.
- **Hierarchy**:
  - `ConnectionDetailsView.connectionDetailsLabel`: `.font(.headline)`, text `.primary`, chevron
    `.secondary`; add `.accessibilityValue(isExpanded ? "Expanded" : "Collapsed")` on the button.
  - `DetailGroupView.detailsTitle`: `.font(.headline)` (was `.title2` semibold), still secondary.
  - `LiveStatsSectionView` header row: `.font(.headline)` (was `.title2`).

### 3. Details expansion without a jump, window-local screen

- `detailsContentHeight` becomes `CGFloat?` starting at `nil`.
- New pure static on `ConnectionDetailsView`:

  ```swift
  static func detailsScrollHeight(contentHeight: CGFloat?, cap: CGFloat) -> CGFloat
  ```

  returns `0` when `contentHeight` is nil, otherwise `min(contentHeight, cap)`. The scroll view uses
  `.frame(height: Self.detailsScrollHeight(contentHeight: detailsContentHeight, cap: maxDetailsHeight))`.
  The inner content's `onGeometryChange` still reports its natural height while the frame is 0, so the
  second pass grows straight to the right size (animated when animations are on), with no oversized
  first frame.
- **Window screen**: new `QuickNetStats/Views/Modifiers/WindowScreenReader.swift` with an
  `NSViewRepresentable` whose `NSView` subclass reports `window?.screen` from
  `viewDidMoveToWindow()` and on `NSWindow.didChangeScreenNotification` for its window (observer
  removed when the window changes). Exposed as
  `func onWindowScreenChange(_ action: @escaping (NSScreen?) -> Void) -> some View` (installed as a
  zero-size `.background`). `ConnectionDetailsView` stores `@State private var screen: NSScreen?`
  and `maxDetailsHeight` reads `(screen ?? NSScreen.main)?.frame.height` / `.visibleFrame.height`.
  The existing tested `maxDetailsHeight(screenHeight:visibleHeight:chromeHeight:)` is unchanged.

---

## Edge Cases & Constraints

- **Deployment target macOS 13.** `symbolEffect(.rotate)` is macOS 15+ and
  `AccessibilityNotification.Announcement` macOS 14+ — both gated with fallbacks. `Task.sleep(for:)`
  is macOS 13+.
- **Nil values.** Copy of an unavailable IP is a no-op: `CopyButton` is disabled for nil and
  `Clipboard.copy` returns false for nil/empty, so no "Copied" for "Unavailable".
- **Rapid re-taps.** `.task(id: confirmationID)` restarts the 1.2s timer; the confirmation never
  clears early from a stale task.
- **Popover closes during confirmation.** The task is cancelled with the view; `@State` resets on
  next appearance. No leak.
- **Live Stats rows** stay plain text (values churn every second; not copyable, unchanged).
- **Very long values** (IPv6 public IP): `minimumScaleFactor` shrinks before truncating;
  `DetailGroupView` keeps its middle truncation.
- **Unit-testability.** View-only behavior (animations, announcements, rotation, screen reader
  callbacks) is verified via previews/manual check; logic is pushed into `Clipboard`,
  `NetStatsViewModel`, and `ConnectionDetailsView` statics, which are unit tested.
- **Manual verification required**: UI automation is permission-blocked on this machine, so popover
  behavior must be checked by hand (previews render via Xcode MCP `RenderPreview`).

---

## Implementation Steps

Work directly on `develop` (no branch, no worktree). Build/test through the Xcode MCP tools
(`BuildProject`, `RunSomeTests`, `RunAllTests`, `RenderPreview`; tab id from `XcodeListWindows`).
CLI fallback: `caffeinate -dims env DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'`.
New files under `QuickNetStats/` and `QuickNetStatsTests/` are picked up automatically (synchronized
groups). **Do not commit** — the user commits.

### Task 1: `Clipboard` (TDD)

- [x] Create `QuickNetStatsTests/ClipboardTests.swift` (Swift Testing, `@MainActor` suite) using a
  private pasteboard `NSPasteboard(name: .init("qns-test-\(UUID().uuidString)"))`, released in a
  `defer` with `releaseGlobally()`. Tests:
  - `copy("10.0.0.32", to: pb)` returns `true` and `pb.string(forType: .string) == "10.0.0.32"`
  - `copy(nil, to: pb)` returns `false` and a pre-seeded string `"keep"` is still present
  - `copy("", to: pb)` returns `false` and `"keep"` is still present
- [x] Run the tests; confirm they fail (type missing).
- [x] Create `QuickNetStats/Managers/Clipboard.swift`:
  ```swift
  import AppKit

  enum Clipboard {
      /// Returns false (and leaves the pasteboard untouched) for nil or empty values.
      @discardableResult
      static func copy(_ value: String?, to pasteboard: NSPasteboard = .general) -> Bool {
          guard let value, !value.isEmpty else { return false }
          pasteboard.clearContents()
          return pasteboard.setString(value, forType: .string)
      }
  }
  ```
- [x] Run the tests; confirm they pass.

### Task 2: `NetStatsViewModel` additions (TDD)

- [x] In `QuickNetStatsTests/NetStatsViewModelTests.swift` add parameterized tests:
  - `monochromeColor(for:)`: `(.light, Color.primary)`, `(.dark, Color.secondary)`
  - `accessibilitySummary(includeSSID:)` with `ssid: "HomeNet"`:
    - `mockGoodWifiConnection`, `true` → `"Wi-Fi, HomeNet, link quality Good"`
    - `mockGoodWifiConnection`, `false` → `"Wi-Fi, link quality Good"`
    - `mockBadWifiConnection`, `true` → `"Wi-Fi, HomeNet, link quality Minimal"`
    - `mockGoodEthConnection`, `true` → `"Ethernet, link quality Good"` (SSID ignored off Wi-Fi)
    - `mockExpensiveCellConnection`, `true` → `"Personal Hotspot, link quality Good"`
    - `mockDisconnected`, `true` → `"Disconnected"`
  - `accessibilitySummary` with `ssid: nil` on `mockGoodWifiConnection`, `true` → `"Wi-Fi, link quality Good"`
- [x] Run; confirm failures.
- [x] Implement in `NetStatsViewModel.swift`:
  ```swift
  static func monochromeColor(for colorScheme: ColorScheme) -> Color {
      colorScheme == .dark ? .secondary : .primary
  }

  func accessibilitySummary(includeSSID: Bool) -> String {
      guard netStats.isConnected else { return "Disconnected" }
      var parts = [spokenInterfaceName]
      if includeSSID, isWifiConnection, let ssid { parts.append(ssid) }
      if let quality = netStats.linkQuality, quality != .unknown {
          parts.append("link quality \(quality.description)")
      }
      return parts.joined(separator: ", ")
  }

  private var spokenInterfaceName: String {
      switch netStats.interfaceType {
      case .wifi: return "Wi-Fi"
      case .ethernet: return "Ethernet"
      case .cellular: return "Personal Hotspot"
      default: return "Network"
      }
  }
  ```
  Remove `copyToClipboard(_:)`.
- [x] Run; confirm pass (if `mockDisconnected.isConnected` or mock interface types differ from the
  expectations above, fix the expectation only after checking `NetworkStats.swift` mocks).

### Task 3: Details scroll height (TDD)

- [x] In `QuickNetStatsTests/ConnectionDetailsViewTests.swift` add parameterized test for
  `ConnectionDetailsView.detailsScrollHeight(contentHeight:cap:)`:
  `(nil, 500) → 0`, `(300, 500) → 300`, `(800, 500) → 500`, `(0, 500) → 0`.
- [x] Run; confirm failure.
- [x] Add the static to `ConnectionDetailsView`:
  ```swift
  /// Zero until the content has been measured, so the first expanded frame never renders at the full cap.
  static func detailsScrollHeight(contentHeight: CGFloat?, cap: CGFloat) -> CGFloat {
      guard let contentHeight else { return 0 }
      return min(contentHeight, cap)
  }
  ```
  Change `detailsContentHeight` to `@State private var detailsContentHeight: CGFloat?` and the scroll
  frame to `.frame(height: Self.detailsScrollHeight(contentHeight: detailsContentHeight, cap: maxDetailsHeight))`.
- [x] Run; confirm pass.

### Task 4: Window-local screen

- [x] Create `QuickNetStats/Views/Modifiers/WindowScreenReader.swift` with `WindowScreenReader:
  NSViewRepresentable` (custom `NSView` overriding `viewDidMoveToWindow()`, observing
  `NSWindow.didChangeScreenNotification` for `window`, removing the observer on window change and in
  `deinit`, invoking the callback on the main actor) and
  `extension View { func onWindowScreenChange(_ action: @escaping (NSScreen?) -> Void) -> some View }`
  that installs it as a zero-size `.background`.
- [x] In `ConnectionDetailsView` add `@State private var screen: NSScreen?`, attach
  `.onWindowScreenChange { screen = $0 }` to the root `VStack`, and make `maxDetailsHeight` use
  `let current = screen ?? NSScreen.main`. Update its doc comment (no longer `NSScreen.main`-only).
- [x] Build; run `ConnectionDetailsViewTests`; confirm pass.

### Task 5: `CopyButton` and wiring copy feedback

- [x] Create `QuickNetStats/Views/Camponents/CopyButton.swift` per the Design (state, `.task(id:)`
  reset after `.seconds(1.2)`, gated announcement with fallback, reduce-motion + `animated`, plain
  style, `.focusable(false)`, `.help("Click to copy")`, `.accessibilityHint("Copies to the clipboard")`,
  `.disabled(value == nil)`), with previews for an idle and a nil-value button.
- [x] Update `AddressView` (`isConfirming` parameter, flexible layout from Design §2, accessibility
  label, `contentShape`) and its previews (add a long IPv6 value and a confirming state; delete the
  commented-out preview block).
- [x] Update `NetStatsView.ipButtonsSection` to use `CopyButton(value: vm.publicIP, animated: settings.useAnimations) { AddressView(title: "Public IP", value: vm.publicIP ?? "Unavailable", isConfirming: $0) }`
  (same for Private IP); remove the per-button `.help`, `.buttonStyle`, `.focusable` now owned by
  `CopyButton`.
- [x] Update `DetailGroupView` (`animated` parameter, `CopyButton` per value, remove `copy(_:)`);
  pass `animated: settings.useAnimations` from `ConnectionDetailsView`.
- [x] Build; run all tests; render `AddressView`, `DetailGroupView`, `NetStatsView` previews via
  `RenderPreview` and inspect.

### Task 6: Refresh button and hero accessibility

- [x] In `ContentView` add `@State private var isRefreshing = false`; guard/set/`defer` clear inside
  the refresh `Task`; `.disabled(isRefreshing)`, `.help("Refresh")`, `.accessibilityLabel("Refresh")`;
  `if #available(macOS 15, *), settings.useAnimations` apply `.symbolEffect(.rotate, isActive: isRefreshing)`
  to the image.
- [x] In `NetStatsView` make the hero `HStack` a single accessibility element labeled with
  `vm.accessibilitySummary(includeSSID: settings.showNetworkNames)`.
- [x] Build; confirm no warnings introduced.

### Task 7: Semantic colors and hierarchy

- [x] `NetStatsView`: replace `monochromeColor` computed property with
  `NetStatsViewModel.monochromeColor(for: colorScheme)`; SSID text `.foregroundStyle(.secondary)`.
- [x] `LinkQualityView`: remove the `80×80` frame; empty circles `.foregroundStyle(.quaternary)`;
  caption `.foregroundStyle(.secondary)`.
- [x] `NetworkInterfaceView`: offline icon `.foregroundStyle(.secondary)`.
- [x] `ConnectionDetailsView.connectionDetailsLabel`: `.headline`, primary text, secondary chevron;
  `.accessibilityValue` on the button.
- [x] `DetailGroupView.detailsTitle` and `LiveStatsSectionView` header: `.font(.headline)`.
- [x] Render `NetStatsView` (Good, Disconnected, Constrained + Expensive), `LinkQualityView`, and
  `ConnectionDetailsView` (Wi-Fi expanded, Live) previews; inspect for overflow/clipping.
  /new The `ConnectionDetailsView` "(expanded)"/"Live" previews actually render collapsed (`isExpanded`
  is private `@State` defaulting to `false`), so the expanded layout was checked through the
  `DetailGroupView` and `LiveStatsSectionView` previews instead and must be confirmed in the app.

### Task 8: Verification

- [x] `swiftlint lint` — no new violations in touched files.
- [x] Full test suite passes (`RunAllTests` or CLI fallback); record counts.
- [x] Request code review (`superpowers:requesting-code-review`) on the uncommitted diff and address
  findings.
  /new Addressed: first-measurement height change now animated; `CopyButton` clears its confirmation
  `onDisappear` (MenuBarExtra keeps views alive, so the "@State resets on next appearance" edge case
  above does not hold); hint/help hidden when disabled; generic renamed to `Content`; middle truncation on
  `AddressView` values; extra `accessibilitySummary` tests for nil/unknown link quality.
- [x] Report to the user: summary, test output, previews inspected, and the manual checks they must
  do in the running app (copy confirmation + VoiceOver announcement, refresh rotation/disable,
  expand without jump, popover on a second display).
