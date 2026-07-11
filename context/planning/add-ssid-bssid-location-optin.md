# Plan: Opt-in SSID & BSSID via Location Services

> **Date**: 2026-07-07
> **Scope**: Show the Wi-Fi network name (SSID) below the big Wi-Fi icon in the main window and the
> BSSID inside Connection Details → Interface, unlocked by an opt-in Location Services permission
> flow driven from a new toggle in Settings → Connection Details.
> **Prerequisite**: `feat/detailed-info-dropdown` branch (Connection Details dropdown, Beta 4).

---

## Context

CoreWLAN's `CWInterface.ssid()` / `bssid()` return `nil` on modern macOS unless the app is
authorized for Location Services — Apple treats network identifiers as location-revealing data.
The project has deliberately never called them (`WifiReader` doc comment enforces this). To unlock
them the app needs the sandbox location entitlement, a usage description, and a granted
`CLLocationManager.requestWhenInUseAuthorization()`.

The user-approved design:

- Opt-in **toggle** in the existing **Settings → Connection Details** page, **default off**.
- First toggle-on triggers the system location prompt (with a brief usage string explaining that
  macOS requires location for SSID/BSSID and that location is never collected or stored).
- If the user **refuses**, the toggle stays off. If they **grant**, it turns on; later off→on
  toggles never re-prompt (the OS remembers the grant; we read the current status directly).
- When authorized **and** the toggle is on:
  - **SSID** appears below the big Wi-Fi icon in the main popover window.
  - **BSSID** appears as a row in the **Interface** group of Connection Details.

---

## Overview

```
Settings → Connection Details page
  └── ToggleView "Show network name (SSID) & BSSID"     [Settings.showNetworkNames]
        └── custom Binding ──► LocationPermissionManager (NEW, only CoreLocation import)
                                  .state: notDetermined | authorized | denied
                                  .requestAuthorization(onGrant:)

Popover window
  NetStatsView ── ssid ◄── NetworkDetailsManager.ssid ◄── WifiReading.currentSSID()
  ConnectionDetailsView ── interfaceRows(includeBSSID: settings.showNetworkNames)
        ▲
  ConnectionDetailsManager.details.interface.bssid ◄── WifiSnapshot.bssid ◄── CWInterface.bssid()
```

Data flow stays on the established seams: `WifiReader` remains the ONLY file importing CoreWLAN
and gains the two location-gated reads; a new `LocationPermissionManager` becomes the ONLY file
importing CoreLocation. Display gating is `settings.showNetworkNames` (the reads themselves are
harmless when unauthorized — they just return `nil`, and CoreWLAN never triggers a prompt on its
own; only `CLLocationManager.requestWhenInUseAuthorization()` does).

---

## Design

### 1. Build settings (project.pbxproj — app target, Debug + Release blocks)

The only pbxproj edits allowed are these build-setting lines (never touch file lists — the project
uses filesystem-synchronized groups):

- `ENABLE_RESOURCE_ACCESS_LOCATION = NO;` → `YES;` (two occurrences, the app target's Debug and
  Release configs — currently lines 389 and 440). This injects the
  `com.apple.security.personal-information.location` sandbox entitlement.
- Insert in both blocks, alphabetically among the existing `INFOPLIST_KEY_` entries (after
  `INFOPLIST_KEY_LSUIElement = YES;`):

```
INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "QuickNetStats never collects or stores your location. macOS requires Location Services permission to read the Wi-Fi network name (SSID) and access point address (BSSID).";
```

### 2. `LocationPermissionManager` (new — `QuickNetStats/Managers/LocationPermissionManager.swift`)

The ONLY file importing CoreLocation. Never requests a location fix — authorization alone unlocks
CoreWLAN.

```swift
import Foundation
import CoreLocation

/// The app-level view of Location Services authorization, collapsed to the three
/// states the opt-in toggle cares about.
enum LocationAuthorizationState {
    case notDetermined
    case authorized
    case denied
}

/// Owns the `CLLocationManager` used solely to unlock CoreWLAN's location-gated
/// SSID/BSSID reads. Never requests a location fix. This is the ONLY file that
/// imports CoreLocation.
class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    /// The current authorization state; updates whenever the system reports a change.
    @Published private(set) var state: LocationAuthorizationState

    private let manager: CLLocationManager

    /// Pending grant continuation from `requestAuthorization(onGrant:)`; fired once
    /// the user answers the system prompt with a grant, discarded on refusal.
    private var onGrant: (() -> Void)?

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.state = Self.state(from: manager.authorizationStatus)
        super.init()
        manager.delegate = self
    }

    /// Shows the system location prompt (only possible while `.notDetermined`) and
    /// runs `onGrant` if the user authorizes.
    func requestAuthorization(onGrant: @escaping () -> Void) {
        self.onGrant = onGrant
        manager.requestWhenInUseAuthorization()
    }

    /// Delegate callbacks are not actor-isolated; hop to the main actor before
    /// touching published state.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.apply(status)
        }
    }

    /// Publishes the new state and settles the pending grant continuation.
    private func apply(_ status: CLAuthorizationStatus) {
        state = Self.state(from: status)
        switch state {
        case .authorized:
            onGrant?()
            onGrant = nil
        case .denied:
            onGrant = nil
        case .notDetermined:
            break
        }
    }

    /// Collapses `CLAuthorizationStatus` to the app's three-state view. Unknown
    /// future cases degrade to `.denied` (no prompt, nothing displayed).
    nonisolated static func state(from status: CLAuthorizationStatus) -> LocationAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }
}
```

**Compiler gotchas** (the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`):
- Do NOT list `.authorized` alongside `.authorizedAlways` — on macOS it is a deprecated alias with
  the same raw value and produces a duplicate-case error.
- The delegate method and the static mapper must be `nonisolated` as shown.

### 3. `Settings.showNetworkNames`

`QuickNetStats/Models/Settings.swift` — new key + property following the existing pattern:

```swift
static let showNetworkNames = "showNetworkNames"
```

```swift
/// Opt-in display of the Wi-Fi SSID (main window) and BSSID (Connection Details).
/// Turning it on for the first time triggers the Location Services prompt macOS
/// requires for these reads; see `LocationPermissionManager`.
@AppStorage(UserDefaultsKeys.showNetworkNames)
var showNetworkNames: Bool = false
```

### 4. `WifiReader` — the lifted constraint

The standing "never call `ssid()`/`bssid()`" rule is **deliberately lifted**, in this file only.

- `WifiSnapshot` gains `var bssid: String?`.
- `snapshot(for:)` adds `snapshot.bssid = interface.bssid()` (nil when unauthorized — graceful).
- `WifiReading` protocol gains the main-window read:

```swift
protocol WifiReading {
    func snapshot(for bsdName: String) -> WifiSnapshot?
    /// The SSID of the default Wi-Fi interface; nil off Wi-Fi or when Location
    /// Services authorization is missing.
    func currentSSID() -> String?
}
```

```swift
func currentSSID() -> String? {
    CWWiFiClient.shared().interface()?.ssid()
}
```

- Update the type doc comment: replace the "**`ssid()`/`bssid()` are location-gated and never
  called.**" sentence with one explaining they are now read and return nil without Location
  Services authorization (see `LocationPermissionManager`).

### 5. `NetworkDetailsManager` — SSID for the main window

The popover already fetches the IPs through this manager on open and refresh; the SSID rides along:

- `@Published var ssid: String?`
- `init(session: URLSession = .reachabilitySession, wifiReader: WifiReading = WifiReader())`
- `getAddresses()` adds `self.ssid = wifiReader.currentSSID()`
- `deleteAndGetAddresses()` also nils it first, then re-reads.

### 6. `ConnectionDetails` — BSSID row under Interface

- `Interface` gains `var bssid: String?`.
- `interfaceRows(rateUnit:includeBSSID:)` — the new parameter defaults to `false` so every existing
  call site, preview, and test stays byte-identical:

```swift
func interfaceRows(rateUnit: RateUnit = .bitsPerSecond, includeBSSID: Bool = false) -> [DetailRow] {
```

  The row goes right after "MAC address" (both are L2 identifiers):

```swift
if includeBSSID, let bssid = interface.bssid {
    rows.append(DetailRow(label: "BSSID", value: bssid))
}
```

- `mockWifi` gains `bssid: "aa:bb:cc:11:22:33"` in its `Interface` init.

### 7. `ConnectionDetailsManager` — pass-through

In `fetchDetails()`, the `interface:` group init gains `bssid: wifiSnapshot?.bssid`. Note
`wifiSnapshot` is read before the row is built, exactly as today; no ordering change.

### 8. Settings UI — the opt-in toggle (`ConnectionDetailsSettingsView`)

New `@StateObject private var locationPermission = LocationPermissionManager()` and a new Form
section after "Live Stats":

```swift
Section {
    ToggleView(
        title: "Show network name (SSID) & BSSID",
        variable: showNetworkNamesBinding,
        description: "Displays the Wi-Fi name in the main window and the BSSID in "
            + "'Connection Details'. macOS requires Location Services permission for "
            + "these; your location is never collected or stored."
    )

    if locationPermission.state == .denied {
        HStack {
            Text("Location access is denied. Allow QuickNetStats under Privacy & Security → Location Services.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Open Settings") { openLocationSettings() }
        }
    }
} header: {
    Text("Network Names")
}
```

The custom binding implements the approved first-time-prompt flow — the toggle only lands on `true`
once authorization actually exists:

```swift
/// Bridges the toggle to `Settings.showNetworkNames`, injecting the one-time
/// Location Services prompt: while undetermined the toggle stays off and the
/// system prompt decides; once authorized it flips freely without re-prompting.
private var showNetworkNamesBinding: Binding<Bool> {
    Binding(
        get: { settings.showNetworkNames },
        set: { isOn in
            guard isOn else {
                settings.showNetworkNames = false
                return
            }
            switch locationPermission.state {
            case .authorized:
                settings.showNetworkNames = true
            case .notDetermined:
                locationPermission.requestAuthorization {
                    settings.showNetworkNames = true
                }
            case .denied:
                break   // stays off; the caption below offers the recovery path
            }
        }
    )
}
```

```swift
/// Opens System Settings on the Location Services privacy pane (mirrors
/// `ContentView.openNetworkSettings()`).
private func openLocationSettings() {
    let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
    if let url = URL(string: urlString) {
        NSWorkspace.shared.open(url)
    }
}
```

(`import AppKit` if not already pulled in via SwiftUI.)

### 9. Popover UI

**`NetStatsView`** — `init` gains `ssid: String? = nil` (defaulted so previews keep compiling),
stored on the view model alongside the IPs (`NetStatsViewModel` gains `var ssid: String?` and a
matching defaulted init parameter: `init(netStats:privateIP:publicIP:ssid: String? = nil)`, so
existing view-model tests compile unchanged). The big icon is wrapped so the SSID sits directly below it:

```swift
VStack(spacing: 6) {
    NetworkInterfaceView(
        netInterfaceType: vm.netStats.interfaceType,
        isAvailable: vm.netStats.isConnected,
        linkQualityColor: settings.isColorful ? vm.linkQualityColor : monochromeColor
    )
    .frame(height: 80)

    if settings.showNetworkNames, vm.isWifiConnection, let ssid = vm.ssid {
        Text(ssid)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
```

`NetStatsViewModel` gains the gate (covers real Wi-Fi and hotspot-over-Wi-Fi, and keeps a stale
SSID from showing under the Ethernet icon):

```swift
/// True when the SSID label is meaningful: the active connection actually rides Wi-Fi.
var isWifiConnection: Bool {
    netStats.interfaceType == .wifi || netStats.connectionTechnology == .wifi
}
```

**`ContentView`** passes `ssid: netDetailsManager.ssid` into `NetStatsView`.

**`ConnectionDetailsView`** line 25 becomes:

```swift
DetailGroupView(title: "Interface", rows: details.interfaceRows(rateUnit: settings.interfaceRateUnit, includeBSSID: settings.showNetworkNames))
```

Update the "Good Connection" preview in `NetStatsView` to pass `ssid: "HomeNet 5GHz"` (others keep
the nil default).

---

## Edge Cases & Constraints

- **Refusal is sticky at the OS level.** After a denial, `requestWhenInUseAuthorization()` never
  re-prompts. The toggle therefore snaps back off and the denied caption + "Open Settings" button
  are the only recovery path. This matches the approved design ("if the user refuses, the toggle
  stays off").
- **Authorization revoked later in System Settings** while the toggle is on: `ssid()`/`bssid()`
  return nil, so the SSID label and BSSID row silently disappear (existing nil-omission
  convention). The toggle itself stays on; the denied caption appears next time the settings page
  is opened.
- **LSUIElement intermittent nil**: agent apps on macOS 14.4+ are known to intermittently get nil
  SSID/BSSID even when properly authorized (Apple forums 748518 / 816619, unfixable by
  configuration). Nil-omission degrades gracefully; never show an error state for it.
- **Stale BSSID**: Connection Details are cached after first expand; a grant given while the
  popover data already exists shows up after the refresh button (which calls
  `connectionDetailsManager.refresh()`) or the next fetch. Accepted; no extra invalidation logic.
- **Prompt requires a properly signed app run outside Xcode** (Apple DTS): the system prompt and
  the unlock only behave correctly from an exported/archived signed build. Unit tests cover the
  pure logic; end-to-end verification is manual from a Release export.
- **Grant while off the settings page**: the page-local `LocationPermissionManager` (a
  `@StateObject`) deallocates if the user leaves the page mid-prompt, dropping the `onGrant`
  continuation. On return the state reads `.authorized`, so flipping the toggle again succeeds
  instantly without a prompt. Accepted.
- **No new rows beyond the spec**: SSID appears only under the main icon, BSSID only under
  Interface. The Wi-Fi group of Connection Details is unchanged.
- **CoreLocation confined to `LocationPermissionManager`; CoreWLAN confined to `WifiReader`.**

---

## Implementation Checklist

> **For agentic workers:** Execute task-by-task with TDD. Test command (plain `xcodebuild`
> resolves to CommandLineTools and fails; the Mac sleeps mid-run without `caffeinate`):
>
> ```bash
> caffeinate -dims env DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer \
>   xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'
> ```
>
> Append `-only-testing:QuickNetStatsTests/<SuiteStructName>` for a focused run. Lint with
> `env DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swiftlint lint`.
> **Never run `git commit`/`git add`/`git push`.** New source files auto-join the target
> (filesystem-synchronized groups) — never edit `project.pbxproj` file lists; the ONLY pbxproj
> edits permitted are the build-setting lines in Task 6. Do not `#if DEBUG`-guard preview helpers
> (#Preview bodies compile in Release).

### Task 1: `Settings.showNetworkNames`

- [x] Add a failing test to `QuickNetStatsTests/SettingsTests.swift` inside `SettingsDefaultsTests`, copying the existing UserDefaults-isolated pattern (e.g. `startLiveMonitoringOnOpenDefaultsToFalse`): remove key `Settings.UserDefaultsKeys.showNetworkNames`, defer restore, `#expect(Settings().showNetworkNames == false)`. Run: fails to compile (key missing) — that is the red step.
- [x] Implement: add the `showNetworkNames` key and `@AppStorage` property (Design §3) to `QuickNetStats/Models/Settings.swift`.
- [x] Run the `Settings Defaults` suite — green.

### Task 2: `LocationPermissionManager`

- [x] Create `QuickNetStatsTests/LocationPermissionManagerTests.swift` with a parameterized Swift Testing suite over the mapping (import `CoreLocation` and `Testing`):

```swift
@Test(
    "CLAuthorizationStatus maps to the app's three states",
    arguments: [
        (CLAuthorizationStatus.notDetermined, LocationAuthorizationState.notDetermined),
        (CLAuthorizationStatus.authorizedAlways, LocationAuthorizationState.authorized),
        (CLAuthorizationStatus.denied, LocationAuthorizationState.denied),
        (CLAuthorizationStatus.restricted, LocationAuthorizationState.denied),
    ]
)
func statusMapping(status: CLAuthorizationStatus, expected: LocationAuthorizationState) {
    #expect(LocationPermissionManager.state(from: status) == expected)
}
```

- [x] Run — fails to compile (type missing).
- [x] Create `QuickNetStats/Managers/LocationPermissionManager.swift` exactly as in Design §2 (mind the two compiler gotchas).
- [x] Run the new suite — green. (`LocationAuthorizationState` needs no explicit `Equatable`; enums without associated values get it for free, but the test needs it usable — add `: Equatable` if `#expect` complains.)

### Task 3: `WifiReader` — bssid in snapshot + `currentSSID()`

- [x] Add `var bssid: String?` to `WifiSnapshot`, add `currentSSID()` to the `WifiReading` protocol and `WifiReader` (Design §4), update the type doc comment, and update `MockWifiReader` in `QuickNetStatsTests/ConnectionDetailsManagerTests.swift` to conform:

```swift
final class MockWifiReader: WifiReading {
    var result: WifiSnapshot?
    var currentSSIDResult: String?
    private(set) var callCount = 0
    init(result: WifiSnapshot?, currentSSID: String? = nil) {
        self.result = result
        self.currentSSIDResult = currentSSID
    }
    func snapshot(for bsdName: String) -> WifiSnapshot? {
        callCount += 1
        return result
    }
    func currentSSID() -> String? { currentSSIDResult }
}
```

  (No unit test can exercise the real CoreWLAN reads; the seam is the test surface — Tasks 4–5 cover it.)
- [x] Full test run — green (this task must not change any behavior).

### Task 4: `ConnectionDetails` — BSSID row

- [x] Add failing tests to `QuickNetStatsTests/ConnectionDetailsTests.swift` (match the file's existing style):

```swift
@Test("interfaceRows includes BSSID after MAC address when opted in")
func interfaceRowsIncludeBSSIDWhenOptedIn() {
    let rows = ConnectionDetails.mockWifi.interfaceRows(includeBSSID: true)
    let labels = rows.map(\.label)
    #expect(rows.contains(DetailRow(label: "BSSID", value: "aa:bb:cc:11:22:33")))
    #expect(labels.firstIndex(of: "BSSID") == labels.firstIndex(of: "MAC address").map { $0 + 1 })
}

@Test("interfaceRows omits BSSID by default")
func interfaceRowsOmitBSSIDByDefault() {
    let labels = ConnectionDetails.mockWifi.interfaceRows().map(\.label)
    #expect(!labels.contains("BSSID"))
}

@Test("interfaceRows omits BSSID when the value is missing")
func interfaceRowsOmitNilBSSID() {
    var details = ConnectionDetails.mockWifi
    details.interface.bssid = nil
    let labels = details.interfaceRows(includeBSSID: true).map(\.label)
    #expect(!labels.contains("BSSID"))
}
```

- [x] Run — red.
- [x] Implement Design §6: `Interface.bssid`, the `includeBSSID` parameter and row, `mockWifi` gains `bssid: "aa:bb:cc:11:22:33"`.
- [x] Run the `ConnectionDetails` suite — green.

### Task 5: `ConnectionDetailsManager` pass-through

- [x] Add a failing test to `QuickNetStatsTests/ConnectionDetailsManagerTests.swift`: give the `fullWifi` fixture `bssid: "de:ad:be:ef:00:01"` (add the field to the fixture init), fetch with the standard mocks (copy the `fetchAssemblesGroups` arrangement), `#expect(manager.details?.interface.bssid == "de:ad:be:ef:00:01")`.
- [x] Run — red.
- [x] Implement Design §7: pass `bssid: wifiSnapshot?.bssid` in `fetchDetails()`.
- [x] Run the `ConnectionDetailsManager` suite — green.

### Task 6: `NetworkDetailsManager.ssid` + build settings

- [x] Add a failing test to `QuickNetStatsTests/NetworkDetailsManagerTests.swift` (reuse `MockWifiReader` — same module):

```swift
@Test("getAddresses populates the SSID from the Wi-Fi reader")
func ssidFetched() async {
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        return (response, Data())
    }

    let manager = NetworkDetailsManager(
        session: mockSession(),
        wifiReader: MockWifiReader(result: nil, currentSSID: "HomeNet")
    )
    await manager.getAddresses()

    #expect(manager.ssid == "HomeNet")
}
```

- [x] Run — red.
- [x] Implement Design §5 in `QuickNetStats/Managers/NetworkDetailsManager.swift`.
- [x] Run the `NetworkDetailsManager` suite — green.
- [x] Apply the pbxproj build-setting edits from Design §1 (both app-target blocks: `ENABLE_RESOURCE_ACCESS_LOCATION = YES;` and the `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` line). These are the ONLY pbxproj lines touched.
- [x] Full build succeeds (`xcodebuild ... build` variant of the command above).

### Task 7: Settings UI toggle

- [x] Implement Design §8 in `QuickNetStats/Views/SettingsView/ConnectionDetailsSettingsView.swift` (StateObject, "Network Names" section, custom binding, denied caption, `openLocationSettings()`). No unit test — SwiftUI + TCC; verified by build, previews, and the manual pass below.
- [x] Full build succeeds; existing previews still compile.

### Task 8: Popover UI

- [ ] Add a failing test for the gate to `QuickNetStatsTests/NetStatsViewModelTests.swift` (match the file's existing style; note the wired-hotspot mock is `false` because its technology is `.wiredEthernet`):

```swift
@Test(
    "isWifiConnection is true only when the connection rides Wi-Fi",
    arguments: [
        (NetworkStats.mockGoodWifiConnection, true),
        (NetworkStats.mockGoodEthConnection, false),
        (NetworkStats.mockConstrainedExpensiveCellConnection, true),   // hotspot over Wi-Fi
        (NetworkStats.mockExpensiveCellConnection, false),             // hotspot over cable
        (NetworkStats.mockDisconnected, false),
    ]
)
func isWifiConnectionGate(netStats: NetworkStats, expected: Bool) {
    let vm = NetStatsViewModel(netStats: netStats, privateIP: nil, publicIP: nil)
    #expect(vm.isWifiConnection == expected)
}
```

- [x] Run — red (`isWifiConnection` missing).
- [x] Implement Design §9: `NetStatsViewModel` (`ssid` + `isWifiConnection`), `NetStatsView` (init param, VStack under the icon, "Good Connection" preview gains `ssid: "HomeNet 5GHz"`), `ContentView` passes `netDetailsManager.ssid`, `ConnectionDetailsView` passes `includeBSSID: settings.showNetworkNames`.
- [x] Run the `NetStatsViewModel` suite — green.

### Task 9: Full verification

- [x] Full test suite — `** TEST SUCCEEDED **` (trust the marker, not the interleaved case counts).
- [x] `swiftlint lint` — 0 violations.
- [x] Check every box above; append honest Implementation Notes (deviations, observations) to this file.

### Manual verification (Federico, from an exported signed build)

- [ ] Toggle on in Settings → Connection Details → system prompt appears with the usage string.
- [ ] Refuse → toggle stays off; denied caption + "Open Settings" appear; re-toggling does not re-prompt (macOS behavior) — recovery only via System Settings.
- [ ] Grant → toggle turns on; SSID shows under the Wi-Fi icon; BSSID row shows under Interface after a refresh/expand.
- [ ] Toggle off → both disappear immediately; toggle back on → no prompt, values return.
- [ ] On Ethernet-primary with Wi-Fi also connected: no SSID under the Ethernet icon.

---

## Implementation Notes

> **Date executed**: 2026-07-07 — TDD, task-by-task, all 9 tasks green.

### Deviations from the plan's exact code (all minimal, compiler-driven)

- **`LocationPermissionManager.swift` needs `import Combine`.** Design §2 lists only
  `Foundation` + `CoreLocation`, but `@Published` / `ObservableObject` conformance fails to
  compile without `Combine` (`initializer 'init(wrappedValue:)' is not available due to missing
  import of defining module 'Combine'`). Added `import Combine` — matches the other managers
  (`NetworkDetailsManager`, `ConnectionDetailsManager`) which already import it. The two documented
  compiler gotchas (no `.authorized` alias next to `.authorizedAlways`; `nonisolated` delegate +
  `Task { @MainActor }` hop) were correct as written and needed no change.

- **`NetStatsViewModel.swift` needs `import Network`.** Design §9's `isWifiConnection` compares
  `netStats.connectionTechnology == .wifi`, and `connectionTechnology` is
  `NWInterface.InterfaceType`, so referring to the `.wifi` case requires `Network` imported (the
  file previously imported only `SwiftUI`; `NetStatsView.swift` already imports `Network`). Added
  `import Network`.

- **`ConnectionDetailsView.swift` line 25 wrapped for line length.** Adding
  `includeBSSID: settings.showNetworkNames` pushed the single-line `DetailGroupView(title:
  "Interface", …)` call to 163 chars (SwiftLint `line_length` warns at 160). Split the call across
  multiple lines; semantically identical, and `swiftlint lint` then reported 0 violations.

### Observations

- **Pre-existing-style async warning on the new parameterized test.** `isWifiConnectionGate`'s
  `arguments:` array references the `NetworkStats.mock*` statics, which are `MainActor`-isolated
  under the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting, so the macro expansion
  emits `expression is 'async' but is not marked with 'await'; this is an error in the Swift 6
  language mode`. This is the same shape as the pre-existing `linkQualityColorMapping` test in the
  same file; harmless under the project's Swift 5 mode (`-swift-version 5`), it is a warning not an
  error, the test executes and all 5 cases pass. Left as-is to match the plan's provided test code
  and the surrounding file style.

- **pbxproj edits were confined to the four allowed build-setting lines.** In both the app target's
  Debug and Release blocks: `ENABLE_RESOURCE_ACCESS_LOCATION = NO;` → `YES;` and a new
  `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` line inserted alphabetically after
  `INFOPLIST_KEY_NSHumanReadableCopyright`. No file-list entries were touched; the two new `.swift`
  files auto-joined the target via the filesystem-synchronized group.

- **Framework confinement preserved.** CoreWLAN remains imported only in `WifiReader.swift`
  (SSID/BSSID reads added there); CoreLocation only in `LocationPermissionManager.swift`.

- **Final verification:** full `xcodebuild test` → `** TEST SUCCEEDED **`; `swiftlint lint` →
  `Found 0 violations`. The end-to-end Location Services prompt cannot be exercised from unit tests
  (requires a signed build run outside Xcode per Apple DTS) — the Manual verification checklist
  above is left for Federico.

- **Post-implementation fix (user-tested, 2026-07-07): restart required after first grant.**
  Manual testing showed CoreWLAN does not pick up a freshly granted Location Services permission
  in the running process — `ssid()`/`bssid()` stay nil until the app relaunches. Added a
  "Restart QuickNetStats" alert in `ConnectionDetailsSettingsView`, shown only from the
  first-grant path (`requestAuthorization` completion), with "Quit Now" (`NSApp.terminate`) and
  "Later" buttons. Later off→on toggles never show it (permission already applied at launch).
