# Plan: Customizable Units for Connection Details

> **Date**: 2026-07-06
> **Scope**: A new Settings page letting the user choose, per rate-bearing Connection Details
> section, whether rates display in bits-per-second (bps/Kbps/Mbps/Gbps) or bytes-per-second
> (B/s/KB/s/MB/s/GB/s), backed by one shared bits↔bytes conversion/formatting utility.
> **Prerequisite**: The Connection Details dropdown and its coverage expansion
> (`add-connection-details-dropdown.md`, `expand-connection-details-coverage.md`).

---

## Context

All rate values in the dropdown are currently formatted in their native unit family: Link speed
and Tx rate in bits (Mbps/Gbps, via `ConnectionDetails.Interface.linkSpeedText` and
`LiveConnectionStats.txRateText`), Download/Upload throughput in bytes (`LiveConnectionStats.rateText`).
Users think in different units (ISPs sell Mbps; downloads read in MB/s), so each section gets a
user preference. Canonical example: Link speed natively 210 Mbps → switchable to "26.25 MB/s".

Three sections carry bit/byte rates:

| Settings section | Rows governed | Native unit |
|---|---|---|
| Interface | Link speed | bits |
| Wi-Fi | Tx rate (rendered in the Live grid, but it is Wi-Fi RF data) | bits |
| Live | Download, Upload | bytes |

Defaults equal the native unit, so the default UI is pixel-identical to today. Packets/Errors/
Drops are counts, not data rates — unaffected. Tx power (mW) unaffected.

---

## Overview

```
Settings (@AppStorage, 3 new prefs)          DataRate.swift (NEW, shared utility)
 ├─ interfaceRateUnit : RateUnit = .bits      ├─ enum RateUnit: String { bits, bytes }
 ├─ wifiRateUnit      : RateUnit = .bits      ├─ bitsToBytes / bytesToBits   (÷8 / ×8)
 └─ liveRateUnit      : RateUnit = .bytes     └─ text(bitsPerSecond:in:) / text(bytesPerSecond:in:)
                                                  auto-scaled multiples, ≤2 decimals, zeros stripped
SettingsView
 └─ new page "Connection Details" (SettingsViewModel.SettingsPage.connectionDetails)
     └─ ConnectionDetailsSettingsView: three labeled unit pickers (Interface / Wi-Fi / Live)

ConnectionDetailsView (dropdown)
 ├─ details.interfaceRows(rateUnit: settings.interfaceRateUnit)
 └─ LiveStatsSectionView(..., liveUnit: settings.liveRateUnit, wifiRateUnit: settings.wifiRateUnit)
```

---

## Design

### Shared utility (`QuickNetStats/Models/DataRate.swift`, NEW)

```swift
/// The unit family used to display a data rate.
enum RateUnit: String, CaseIterable, Identifiable {
    case bitsPerSecond = "bps"
    case bytesPerSecond = "B/s"
    var id: String { rawValue }
    var displayName: String   // "Bits per second (Mbps)" / "Bytes per second (MB/s)"
}

/// Shared bits <-> bytes conversion and auto-scaling rate formatting.
enum DataRate {
    static func bitsToBytes(_ bitsPerSecond: Double) -> Double    // ÷ 8
    static func bytesToBits(_ bytesPerSecond: Double) -> Double   // × 8
    static func text(bitsPerSecond: Double, in unit: RateUnit) -> String
    static func text(bytesPerSecond: Double, in unit: RateUnit) -> String
}
```

Formatting rules (both families, base-1000 multiples):
- bits: `bps`, `Kbps`, `Mbps`, `Gbps`; bytes: `B/s`, `KB/s`, `MB/s`, `GB/s`.
- Scale to the largest multiple ≥ 1; up to 2 decimals, trailing zeros stripped
  ("866 Mbps", "1 Gbps", "2.5 Gbps", "26.25 MB/s", "999 B/s").
- Conversions: 210 Mbps → "26.25 MB/s"; 866 Mbps → "108.25 MB/s"; 1 GB/s → "8 Gbps".

Existing formatters become thin wrappers over `DataRate` (single source of truth):
- `ConnectionDetails.Interface` link-speed formatting → `DataRate.text(bitsPerSecond: mbps * 1e6, in: unit)`.
- `LiveConnectionStats.rateText` (bytes) and `txRateText` (bits) → routed through `DataRate`.
Their current default-unit outputs must not change (existing tests are the regression net; the
current "866 Mbps" / "1.2 MB/s"-style strings stay identical for default units).

### Settings model (`QuickNetStats/Models/Settings.swift`)

Three new `@AppStorage` properties (RawRepresentable-String storage, macOS 13-safe), defaults =
native units, with `UserDefaultsKeys` entries following the existing pattern:

```swift
@AppStorage(UserDefaultsKeys.interfaceRateUnit) var interfaceRateUnit: RateUnit = .bitsPerSecond
@AppStorage(UserDefaultsKeys.wifiRateUnit)      var wifiRateUnit: RateUnit = .bitsPerSecond
@AppStorage(UserDefaultsKeys.liveRateUnit)      var liveRateUnit: RateUnit = .bytesPerSecond
```

### Model changes (unit threading — views stay dumb, models stay Settings-free)

- `ConnectionDetails.interfaceRows` becomes `interfaceRows(rateUnit: RateUnit = .bitsPerSecond)`;
  only the "Link speed" row's value changes with the unit. (Default argument keeps previews and
  existing call sites/tests compiling unchanged.)
- `LiveConnectionStats`: `downloadText`/`uploadText`/`txRateText` gain parameterized variants
  `downloadText(in:)`, `uploadText(in:)`, `txRateText(in:)`; the existing computed properties
  delegate to them with native units.
- No stored model data changes — native values remain the stored truth; units are display-only.

### Settings UI

- `SettingsViewModel.SettingsPage`: new case `connectionDetails`, inserted after `.visuals`.
  Title "Connection Details", icon `"gauge.with.dots.needle.67percent"` (fallback if unavailable
  at target: `"speedometer"`), color `.orange` (distinct from the existing red/blue/green/gray).
- New view `QuickNetStats/Views/SettingsView/ConnectionDetailsSettingsView.swift`, wired into
  `SettingsView`'s page switch like the existing pages. Content: three pickers (segmented or the
  project's `PickerView` component — follow whichever pattern `NotificationView` uses), one per
  section, each with a caption describing which rows it affects:
  - "Interface — Link speed"
  - "Wi-Fi — Tx rate"
  - "Live — Download and Upload"
- Preview with a `Settings()` environment object, like sibling pages.

### Dropdown wiring

- `ConnectionDetailsView` (has `settings` already): pass `settings.interfaceRateUnit` into
  `interfaceRows(rateUnit:)`; pass `settings.liveRateUnit` and `settings.wifiRateUnit` into
  `LiveStatsSectionView` as two new `let` parameters, used for Download/Upload and Tx rate
  respectively. Because `settings` is an `@EnvironmentObject`, changing a picker re-renders the
  dropdown automatically — no extra plumbing.

### Testing (Swift Testing, TDD)

- **`DataRateTests` (new file)**: conversion round-trips (÷8/×8), formatting across all multiples
  in both families, decimal/stripping rules, the canonical 210 Mbps → "26.25 MB/s", boundary
  values (999 vs 1000), zero.
- **`ConnectionDetailsTests`**: Link speed row in both units; default-argument path unchanged.
- **`LiveConnectionStatsTests`**: parameterized text funcs in both units; existing computed
  properties still native (regression).
- **`SettingsTests`**: `RateUnit` raw values and id; the three new preference defaults
  (UserDefaults-isolated like `keepDetailsExpanded`'s test).
- **`SettingsViewModelTests`**: update `allCases` count 4 → 5 and add the new page's
  title/icon/color to the parameterized cases (existing tests WILL fail until updated — that is
  the expected RED step, not collateral damage).

---

## Edge Cases & Constraints

- **Numeric fidelity**: conversion before scaling (single Double division) — no compounding
  rounding; 2-decimal display rounding only at the end.
- **`rateText`'s current outputs** (used by Download/Upload today) must be reproduced exactly by
  the `DataRate` bytes-family path for default units — diff the formatting rules first, port the
  existing rules rather than inventing new ones, and let the existing tests arbitrate.
- **Sub-1 bps/B/s values**: clamp to base unit with the same ≤2-decimal rule ("0.13 B/s" is
  acceptable; no sub-multiples).
- **AppStorage + enum**: `@AppStorage` requires `RawRepresentable where RawValue == String` —
  `RateUnit: String` satisfies it; a stale/unknown stored raw value falls back to the default via
  the property's default argument semantics (verify: AppStorage keeps the default when the stored
  raw doesn't decode).
- **macOS 13 floor**: SF Symbol availability for the page icon must be verified at target
  (fallback listed). No other new API.
- **Out of scope**: per-row unit overrides, additional unit families (e.g. Kibi/Mebi base-1024),
  persisting a unit choice into copied clipboard values (rows copy the displayed string, as they
  already do).

---

## Implementation Plan

> **For agentic workers:** execute task-by-task with strict TDD (failing tests → run → implement
> → green). Check each box immediately on step completion. Invoke
> `swift-testing-expert:swift-testing-expert` before test work and
> `swiftui-expert:swiftui-expert-skill` before view work. Fill "Implementation Notes" with real
> observations only. **Never `git add`/`commit`/`push`.** Do not edit `project.pbxproj`.
> Build/test: `caffeinate -dims env DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'`
> (plain `xcodebuild` fails; the Mac sleeps mid-run without caffeinate). Baseline: 231 test cases
> green (xcodebuild counts parameterized arguments individually), swiftlint 0. SourceKit editor
> diagnostics are stale-indexer noise.

### Task 1: `DataRate` shared utility

- [x] **Step 1**: New `QuickNetStatsTests/DataRateTests.swift` with failing tests per Design
  (conversions, both formatting families across all multiples, 210 Mbps → "26.25 MB/s",
  stripping/boundary/zero rules). First diff `LiveConnectionStats.rateText`'s existing rules and
  encode them as the bytes-family expectations.
- [x] **Step 2**: Run → compile failure. **Step 3**: Implement `QuickNetStats/Models/DataRate.swift`
  (`RateUnit` + `DataRate`). **Step 4**: Green.

### Task 2: Route existing formatters through `DataRate`

- [x] **Step 1**: Failing tests: `interfaceRows(rateUnit: .bytesPerSecond)` Link-speed row
  ("210 Mbps" fixture → "26.25 MB/s"); `downloadText(in:)`/`uploadText(in:)`/`txRateText(in:)`
  both units; existing computed properties unchanged.
- [x] **Step 2**: Run → fail. **Step 3**: Implement (thin wrappers, default arguments preserve
  all current call sites). **Step 4**: Full suite green — existing formatting tests are the
  regression net.

### Task 3: Settings model

- [x] **Step 1**: Failing tests: three new preference defaults (UserDefaults-isolated, pattern of
  `keepDetailsExpandedDefaultsToFalse`), `RateUnit` raw values/ids.
- [x] **Step 2**: Run → fail. **Step 3**: Implement `@AppStorage` props + keys. **Step 4**: Green.

### Task 4: Settings page

- [x] **Step 1**: Update `SettingsViewModelTests` FIRST (count 5, new page title/icon/color
  params) → run → RED. Invoke swiftui-expert.
- [x] **Step 2**: Add `SettingsPage.connectionDetails` (after `.visuals`) and create
  `ConnectionDetailsSettingsView` with the three pickers + captions, wired into `SettingsView`'s
  switch; preview added. Verify the SF Symbol renders at macOS 13 target (fallback per Design).
- [x] **Step 3**: Full suite green; build succeeds.

### Task 5: Dropdown wiring

- [x] **Step 1**: Invoke swiftui-expert (if context lost). Thread `settings.interfaceRateUnit`
  into `interfaceRows(rateUnit:)` in `ConnectionDetailsView`; add `liveUnit`/`wifiRateUnit`
  parameters to `LiveStatsSectionView` and use them for Download/Upload/Tx rate; update its
  previews and any other call sites.
- [x] **Step 2**: Build succeeds; full suite green.

### Task 6: Final verification

- [x] **Step 1**: swiftlint → 0 violations.
- [x] **Step 2**: Full suite green; re-read Design and confirm every behavior implemented or its
  absence noted below; record deviations.

---

## Implementation Notes (deviations & observations)

### Formatting-rule reconciliation (Tasks 1–2)

- **Bytes-family conflict (ported the OLD rule).** The new `DataRate` bytes formatter uses the
  uniform "≤2 decimals, trailing zeros stripped" rule (required for the canonical 210 Mbps →
  "26.25 MB/s" and "108.25 MB/s"). The OLD `LiveConnectionStats.rateText` instead uses fixed
  `%.1f` for KB/s and above (e.g. `340.0 KB/s`, `1000.0 KB/s`, `1.0 MB/s`) and whole B/s. These
  genuinely conflict on whole KB/s+ values (`340 KB/s` vs `340.0 KB/s`), which the existing tests
  assert. Per the hard rule I PORTED/KEPT the OLD rule for the default bytes path: `rateText(_:)`
  is unchanged, and `downloadText/uploadText` (default `.bytesPerSecond`) still route through it.
  Only the NON-default (converted-to-bits) display of throughput uses `DataRate`. Net effect: the
  default bytes display keeps `%.1f`; a link/Tx rate CONVERTED to bytes uses `DataRate`'s 2-decimal
  form (this asymmetry is only observable across different rows and is required to satisfy both
  the regression net and the canonical `26.25 MB/s` example).
- **Bits family (no default-output change).** `ConnectionDetails.linkSpeedText(_:)` (native bits,
  used by the default interface Link-speed row and default Tx-rate row) is kept BYTE-FOR-BYTE: the
  unit-aware `linkSpeedText(_:in:)` returns the OLD formatter verbatim for `.bitsPerSecond` and only
  routes through `DataRate` for `.bytesPerSecond`. This avoids a latent refinement (OLD rounds sub-
  1000 Mbps to a whole number, e.g. `866.7 → "867 Mbps"`, whereas `DataRate` would keep `"866.7
  Mbps"`), so every default bits output is unchanged for all inputs, not just the tested ones.
- **API shape.** Verified empirically (swiftc) that a computed `var` and a same-named method with
  arguments coexist in Swift and disambiguate by call syntax, so `var interfaceRows` /
  `var downloadText` / `var uploadText` / `var txRateText` remain as native-unit aliases delegating
  to the new `interfaceRows(rateUnit:)` / `downloadText(in:)` / `uploadText(in:)` / `txRateText(in:)`
  methods. All existing property call sites (views, previews, tests) compiled unchanged — the
  plan's "default arguments preserve call sites" claim held.
- **Test count:** baseline 231 → 262 test cases (+31 new), 0 failures, `** TEST SUCCEEDED **`.

### Settings model (Task 3)

- **AppStorage fallback confirmed empirically.** Stored `"garbage-not-a-unit"` under the
  `interfaceRateUnit` key, then read `Settings().interfaceRateUnit` → returned `.bitsPerSecond`
  (the property default). So an unknown/stale stored raw value falls back to the default, as the
  Edge Cases section predicted. (Verified with a throwaway test that was then removed.)
- **RateUnit raw/id coverage placement.** The plan listed "RateUnit raw values and id" under
  `SettingsTests`; those assertions already live in `RateUnitTests` (in `DataRateTests.swift`,
  Task 1), so I did not duplicate them in `SettingsTests` — only the three preference-default tests
  were added there.

### Settings page (Task 4)

- **SF Symbol — used the fallback `speedometer`.** Checked the system CoreGlyphs metadata
  (`/System/Library/CoreServices/CoreGlyphs.bundle/.../name_availability.plist`):
  `gauge.with.dots.needle.67percent` → release **2023** (SF Symbols 5 / macOS 14+), so it is NOT
  available at the macOS 13.0 deployment floor. `speedometer` → release 2019 (macOS 10.15+), always
  available. Icon for `.connectionDetails` is therefore `"speedometer"` (the plan's designated
  fallback), and `SettingsViewModelTests` asserts that value.
- **Page order / colors.** `SettingsPage` enum order is `menubar, visuals, connectionDetails,
  notifications, about` (inserted after `.visuals` per Design). Color `.orange`, distinct from the
  existing red/blue/green/gray.
- **View pattern.** `ConnectionDetailsSettingsView` mirrors `VisualsView`/`NotificationView`
  (`@ObservedObject settings`, `Form { Section }`, `.formStyle(.grouped)`, `PickerView` with
  `$settings.<unit>` bindings, `#Preview` with `Settings()`). Pickers iterate `RateUnit.allCases`
  using `displayName`. Not render-tested via live preview (Xcode MCP requires a running Xcode);
  verified by successful compile + green suite instead.

### Final verification (Task 6)

- **swiftlint:** `Found 0 violations, 0 serious in 38 files` for the project scope
  (`.swiftlint.yml` sets `included: QuickNetStats`, so test files are intentionally out of scope —
  the baseline "0 violations" has always meant the app source only).
  - Linting the modified test files directly surfaces 8 `trailing_comma` *warnings* (not serious)
    in `arguments:` arrays. These are the pre-existing convention across every test file in the
    repo (e.g. the original `SettingsViewModelTests`/`SettingsTests` arrays already trail commas);
    left unchanged so the new `DataRateTests` stays consistent with its siblings.
- **Full suite:** 231 baseline → **268 test cases**, **0 failures**, `** TEST SUCCEEDED **`.
- **Default-unit outputs byte-identical (verified):** every pre-existing regression assertion
  passed unchanged — `rateTextBoundaries` (999 B/s, 1.0 KB/s, 1000.0 KB/s, 1.0 MB/s, 1.5 GB/s),
  `throughputText` (1.2 MB/s, 340.0 KB/s), `nativeComputedPropertiesUnchanged` (210 → 210 Mbps),
  `linkSpeedMbps`/`linkSpeedOneGbps`/`linkSpeedFractionalGbps` (866 Mbps / 1 Gbps / 2.5 Gbps),
  `rfText` (866 Mbps), and the mock link-speed rows.
- **Design cross-check:** all Design behaviors implemented — `DataRate`/`RateUnit`, three
  `@AppStorage` prefs (native defaults), `interfaceRows(rateUnit:)` +
  `downloadText/uploadText/txRateText(in:)` with native-unit delegating aliases, the
  `connectionDetails` settings page + `ConnectionDetailsSettingsView`, and the dropdown wiring
  (`interfaceRateUnit`→Link speed, `liveRateUnit`→Download/Upload, `wifiRateUnit`→Tx rate). No
  behavior omitted.

### Files created / modified

- **Created:** `QuickNetStats/Models/DataRate.swift`,
  `QuickNetStats/Views/SettingsView/ConnectionDetailsSettingsView.swift`,
  `QuickNetStatsTests/DataRateTests.swift`.
- **Modified (source):** `Models/ConnectionDetails.swift`, `Models/LiveConnectionStats.swift`,
  `Models/Settings.swift`, `Views/SettingsView/SettingsViewModel.swift`,
  `Views/SettingsView/SettingsView.swift`, `Views/Camponents/LiveStatsSectionView.swift`,
  `Views/NetStatsView/ConnectionDetailsView.swift`.
- **Modified (tests):** `ConnectionDetailsTests.swift`, `LiveConnectionStatsTests.swift`,
  `SettingsTests.swift`, `SettingsViewModelTests.swift`.
- `project.pbxproj` untouched (filesystem-synchronized groups picked up the new files).
