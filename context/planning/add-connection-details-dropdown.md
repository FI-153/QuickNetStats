# Plan: Connection Details Dropdown

> **Date**: 2026-07-04
> **Scope**: A collapsible "Connection Details" section in the popover, below the public/private IP
> buttons, showing advanced network information (router, DNS, subnet, MAC, IPv6, MTU, DHCP lease,
> Wi-Fi RF stats) plus an opt-in Live section (RSSI/SNR/tx rate/throughput).
> **Prerequisite**: None. Builds on the research inventory of obtainable network information
> (free tier only — SSID/BSSID are location-gated and explicitly out of scope for now).

---

## Context

QuickNetStats today shows connection type, link quality, and the two IP addresses. Power users
want the "archaic" details — gateway, DNS servers, subnet mask, MAC address, MTU, DHCP lease,
Wi-Fi channel/PHY/security, signal strength, live throughput.

A research pass established that everything listed here is obtainable **with the current
entitlements, sandbox-safe, and without any permission prompt**, from four sources:

1. **SystemConfiguration** (already imported): router IP, primary interface, DNS servers, search
   domains, subnet mask, DHCP lease times, hostname — via read-only `SCDynamicStore` `State:/` keys.
2. **BSD layer** (`getifaddrs`, `sysctl`, `ioctl` — already partially used): MAC address, MTU,
   IPv6 address, link speed, per-interface byte counters (→ throughput).
3. **CoreWLAN** (new import, **not** location-gated for these fields): channel number/band/width,
   PHY mode, security, country code, RSSI, noise, transmit rate. Only `ssid()`/`bssid()` are
   location-gated, and those are deferred.
4. **ipify** (existing pattern): public IPv6 via `api6.ipify.org`.

Decisions taken during brainstorming:

- **Approach A**: a new dedicated `ConnectionDetailsManager` (alongside the existing two managers),
  publishing value-type snapshots; composed of small injectable readers.
- **Layout**: grouped subsections, each rendered as a two-column grid.
- **Live data**: a separate section at the bottom of the dropdown, grayed titles-only by default,
  with a "Live" toggle button. Polling runs only while toggled on; closing the popover stops
  polling and resets the button to "Live".
- **Maximal inclusion**: prefer adding a field over debating it; fields can be removed later.

---

## Overview

```
QuickNetStatsApp
 ├─ @StateObject NetworkStatsManager        (existing)
 ├─ @StateObject NetworkDetailsManager      (existing)
 ├─ @StateObject ConnectionDetailsManager   (NEW)
 │        │
 │        │ composes (injectable protocols)
 │        ├─ SystemConfigReading  → SystemConfigReader   (SCDynamicStore)
 │        ├─ InterfaceReading     → InterfaceReader      (getifaddrs / sysctl / ioctl)
 │        ├─ WifiReading          → WifiReader           (CoreWLAN)
 │        └─ URLSession           → public IPv6 (api6.ipify.org)
 │
 └─ ContentView
     └─ NetStatsView
         ├─ interface icon + link quality        (existing)
         ├─ ipButtonsSection                     (existing)
         ├─ ConnectionDetailsView                (NEW — the dropdown)
         │    ├─ DetailGroupView "Interface"     (two-column Grid)
         │    ├─ DetailGroupView "Addressing"
         │    ├─ DetailGroupView "DNS & DHCP"
         │    ├─ DetailGroupView "Wi-Fi"         (hidden on non-Wi-Fi)
         │    └─ LiveStatsSectionView            (grayed → "Live" toggle → polling)
         └─ exceptionDescriptionSection          (existing)

Data flow:
  expand dropdown ──► manager.fetchDetails() ──► @Published details: ConnectionDetails?
  press "Live"    ──► manager.startLive()    ──► 1 s Task loop ──► @Published liveStats
  press "Stop" / collapse / popover closes ──► manager.stopLive() ──► liveStats = nil
  refresh button (existing) ──► manager.refresh() (re-fetch static details if present)
```

---

## Design

### Models (value types, `QuickNetStats/Models/`)

**`ConnectionDetails.swift`** — one immutable snapshot, grouped to mirror the UI:

- `InterfaceDetails`: `bsdName` (`en0`), `displayName` ("Wi-Fi"), `macAddress`, `mtu: Int?`,
  `linkSpeedMbps: Double?`
- `AddressingDetails`: `ipv6Address` (best local IPv6 — global unicast preferred, link-local
  skipped), `publicIPv6`, `subnetMask`, `routerAddress`, `hostname`
- `DnsDhcpDetails`: `dnsServers: [String]`, `searchDomains: [String]`, `dhcpLeaseExpiry: Date?`
- `WifiDetails?` (nil on non-Wi-Fi): `channelNumber: Int`, `band` (2.4/5/6 GHz), `channelWidthMHz`,
  `phyMode` ("802.11ax"), `security` ("WPA3 Personal"), `countryCode`

All leaf fields optional; a nil field means "could not be determined" and its row is omitted.
Static mocks (`mockWifi`, `mockEthernet`, `mockVPN`) for previews and tests, following the
`NetworkStats` mock pattern.

**`LiveConnectionStats.swift`** — one live sample:

- `downloadBytesPerSec: Double?`, `uploadBytesPerSec: Double?` (any interface; nil until the
  second poll tick, since throughput needs a counter delta)
- `rssiDBm: Int?`, `noiseDBm: Int?`, `txRateMbps: Double?` (Wi-Fi only); computed `snrDB: Int?`

Formatting lives with the models as computed properties / small helpers (e.g. "−52 dBm",
"Channel 44 (5 GHz, 80 MHz)", "1.2 MB/s", lease expiry as short absolute date), so views stay dumb
and formatting is unit-testable.

### Readers (protocol seams, `QuickNetStats/Managers/`)

Three small stateless readers, each behind a protocol so the manager is fully testable without
touching real syscalls — the same seam pattern used by `UpdateManager(session:)` and
`NetworkStatsManager(reachabilityChecker:)`:

- **`SystemConfigReading` → `SystemConfigReader`**: one call returning a `SystemConfigSnapshot`
  (primary interface BSD name, router IPv4, DNS servers, search domains, subnet mask for the
  primary service, DHCP lease expiry via `SCDynamicStoreCopyDHCPInfo` +
  `DHCPInfoGetLeaseStartTime`/option 51, local hostname).
- **`InterfaceReading` → `InterfaceReader`**: `snapshot(for bsdName:)` returning MAC address
  (`AF_LINK`), MTU (`if_data.ifi_mtu`), best local IPv6 (`AF_INET6`, global unicast preferred),
  link speed (`ifi_baudrate`), and 64-bit rx/tx byte counters (`sysctl NET_RT_IFLIST2` /
  `if_data64` — avoids 32-bit rollover).
- **`WifiReading` → `WifiReader`**: `import CoreWLAN` (only file that imports it);
  `CWWiFiClient.shared().interface()` → static snapshot (channel/band/width, PHY, security,
  country) and RF sample (RSSI, noise, tx rate). Returns nil cleanly when there is no Wi-Fi
  interface or Wi-Fi is off. **No SSID/BSSID calls anywhere.**

Public IPv6 is not a reader: the manager fetches `https://api6.ipify.org` with an injectable
`URLSession` (default `.reachabilitySession`), mirroring `NetworkDetailsManager`. Failure
(common: no IPv6 connectivity) simply leaves the row out.

### `ConnectionDetailsManager` (`QuickNetStats/Managers/`)

`ObservableObject`, main-actor (project default isolation), created as a root-level `@StateObject`
in `QuickNetStatsApp` alongside the other two managers.

Published state:

- `@Published private(set) var details: ConnectionDetails?` — nil until first expand
- `@Published private(set) var liveStats: LiveConnectionStats?` — nil unless live
- `@Published private(set) var isLive = false`

API:

- `fetchDetails() async` — SC snapshot → primary interface → interface snapshot → Wi-Fi snapshot;
  public IPv6 fetched concurrently (`async let`); assembles and publishes `ConnectionDetails`.
  Called on first expand and by `refresh()`.
- `refresh() async` — re-fetches only if `details != nil` (i.e. the user has opened the dropdown
  at least once); wired into the existing refresh button in `ContentView`.
- `startLive()` / `stopLive()` — toggles a stored `Task` polling every `pollInterval` (default
  1 s, injectable for tests): each tick reads byte counters + RF sample, computes throughput from
  the previous tick's counters (`(now − prev) / elapsed`; negative delta → counter reset → skip),
  publishes a new `LiveConnectionStats`. First tick publishes RF values with nil throughput.
  `stopLive()` cancels the task, clears `liveStats`, sets `isLive = false`. Task body uses
  `[weak self]` and honors cancellation (patterns from `NetworkStatsManager.pollingTask`).
- `init(systemConfig: SystemConfigReading = SystemConfigReader(), interface: InterfaceReading =
  InterfaceReader(), wifi: WifiReading = WifiReader(), session: URLSession = .reachabilitySession,
  pollInterval: TimeInterval = 1.0)`

The manager never throws to the UI: readers return optionals, and whatever is nil is simply absent
from the snapshot.

### Views (`QuickNetStats/Views/NetStatsView/` + `Views/Camponents/`)

**`ConnectionDetailsView`** — owns the dropdown. Placed inside `NetStatsView.body` directly after
`ipButtonsSection` (literally "below the IPs"), receiving the manager via `@ObservedObject`
(passed down from `ContentView`, like the managers `ContentView` already receives).

- Header: a plain-style `Button` ("Connection Details" + rotating chevron) toggling
  `@State private var isExpanded` — custom expander rather than `DisclosureGroup`, whose default
  macOS styling is list-oriented; rotation/expansion animated with `.animation(_:value:)` gated on
  `settings.useAnimations` (existing accessibility-aware setting).
- Expansion state is **not persisted**: fresh popover → collapsed.
- On first expand: `task { await manager.fetchDetails() }`. While `details == nil` show a small
  `ProgressView`.
- On collapse and on `onDisappear` (popover closed): `manager.stopLive()`.
- Hidden entirely when `netStats.isConnected == false`.

**`DetailGroupView`** (Camponents) — reusable: caption (`.caption`, secondary) + `Grid` (macOS 13+)
of label–value `GridRow`s. Labels secondary; values primary, monospaced digits. Each row is a
plain-style `Button` that copies the raw value via the existing clipboard helper, with
`.help("Click to copy")` — consistent with the IP buttons. Rows with nil values are omitted;
a group with zero rows is not rendered. Row content drives Grid column sizing; long values (IPv6)
get `.truncationMode(.middle)` + full value in `.help`.

Groups and rows (maximal inclusion, top to bottom):

| Group | Rows |
|---|---|
| Interface | Name ("Wi-Fi (en0)"), MAC address, MTU, Link speed |
| Addressing | Router, Subnet mask, IPv6 (local), Public IPv6, Hostname |
| DNS & DHCP | DNS servers (comma-joined), Search domains, DHCP lease expires |
| Wi-Fi | Channel ("44 · 5 GHz · 80 MHz"), PHY mode, Security, Country code |

**`LiveStatsSectionView`** (Camponents) — the Live section, always last:

- Caption row: "Live" caption + trailing toggle `Button`: label "Live" (with `waveform` style
  symbol) when idle, "Stop" when polling.
- Body: same two-column grid; rows: Download, Upload (always), RSSI, Noise, SNR, Tx rate
  (Wi-Fi only). When idle: titles visible, values rendered as "—", whole grid
  `.foregroundStyle(.tertiary)` (the "grayed, titles only" state). When live: real values,
  normal styling; a value momentarily unavailable stays "—".
- Pressing Live → `manager.startLive()`; Stop → `manager.stopLive()`. No polling exists in any
  other state.

Previews: `ConnectionDetailsView` previews for Wi-Fi / Ethernet / VPN / loading / live states,
driven by mock readers injected into a preview manager (`ConnectionDetailsManager.preview`
static helpers), following the existing `NetworkStats.mock*` convention.

### Wiring changes (existing files)

- `QuickNetStatsApp`: third `@StateObject`, passed to `ContentView`.
- `ContentView`: passes manager to `NetStatsView`; refresh button additionally calls
  `await connectionDetailsManager.refresh()`.
- `NetStatsView`: new init parameter (the manager), `ConnectionDetailsView` inserted after
  `ipButtonsSection`. Existing previews updated with the preview manager.

### Testing (Swift Testing, `QuickNetStatsTests/`)

- **`ConnectionDetailsManagerTests`** (mock readers, injected fast `pollInterval`): fetch
  assembles all groups; Wi-Fi group nil when wifi reader returns nil; public IPv6 fetched via
  `MockURLProtocol` (existing token-based infrastructure) and absent on failure; `refresh()`
  no-ops before first fetch; `startLive()` publishes RF on first tick and throughput from the
  second; throughput delta math (fabricated counter sequences, including counter-reset → skipped
  sample); `stopLive()` cancels, clears `liveStats`, resets `isLive`; deinit cancels the task.
- **Formatting tests**: dBm/SNR strings, channel string, byte-rate formatting, lease-date
  formatting, IPv6 preference order (global unicast over link-local).
- **Reader smoke tests**: real `SystemConfigReader`/`InterfaceReader`/`WifiReader` calls return
  without crashing; assertions lenient (no assumption of active Wi-Fi or IPv6) so they pass on CI.
- No new singleton-bound state, so no additions to `SingletonBoundSuites`.

---

## Edge Cases & Constraints

- **Ethernet**: Wi-Fi group hidden; Live section shows only Download/Upload.
- **VPN as primary interface** (`utun*`): MAC, link speed, Wi-Fi rows unavailable → omitted;
  router/DNS still shown. The dropdown describes the *primary* interface by design.
- **Disconnected**: dropdown hidden entirely (IP buttons already communicate the state).
- **Static-IP network**: no DHCP lease → row omitted. **No IPv6**: rows omitted.
- **Multiple IPv6 addresses**: prefer global unicast, skip link-local (`fe80::/10`); deterministic
  first match otherwise.
- **Counter rollover / reset**: 64-bit counters via `NET_RT_IFLIST2`; negative deltas skipped.
- **Popover lifecycle**: `onDisappear` is the stop signal for live polling. If the `.window`-style
  `MenuBarExtra` proves not to fire it reliably, fall back to observing
  `NSWindow.willCloseNotification` — verify during implementation.
- **Energy**: zero cost while collapsed or closed; while live, one syscall batch + CoreWLAN read
  per second, stopped the moment the popover closes.
- **macOS 13 target**: everything used is 13-safe (`Grid` 13+, CoreWLAN 10.7+, `getifaddrs`/
  `sysctl` POSIX). No `onChange` (two-parameter form is 14+); lifecycle handled via button
  actions, `.task`, `onDisappear`. No new entitlements; all reads sandbox-safe.
- **Future-proofing caveat**: Apple has historically widened Wi-Fi privacy redaction. If a future
  macOS gates the RF fields, the rows silently degrade to omitted — no crash path.
- **Out of scope**: SSID/BSSID (location-gated — separate future plan), a Settings toggle to hide
  the section, throughput history/graphs, per-interface selection UI.
- **Agreed follow-up (post-feature)**: rows omitted for nil values should eventually explain
  *why* they are missing (e.g. "No DHCP lease — static IP") instead of disappearing silently.
  To be designed and added once this feature has landed.

---

## Implementation Plan

> **For agentic workers:** Execute task-by-task with TDD (superpowers:test-driven-development).
> Check each `- [x]` box immediately upon completing the step. Invoke
> `swift-testing-expert:swift-testing-expert` before writing test files and
> `swiftui-expert:swiftui-expert-skill` before the view tasks (CLAUDE.md requirement).

**Goal:** Ship the Connection Details dropdown described in the design above.

**Architecture:** New value models + three injectable readers + `ConnectionDetailsManager`
+ three new views, wired into the existing app scaffolding. TDD for all logic; previews + build
verification for views.

### Global Constraints

- macOS 13.0 deployment target; `#available` guards only where APIs demand it (none expected).
- `ObservableObject`/`@Published` (NOT `@Observable` — that's macOS 14+). No `onChange` with the
  two-parameter closure (14+). Project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- Swift Testing (`import Testing`, `#expect`) — never XCTest.
- **Never call `ssid()` or `bssid()`** on `CWInterface` — location-gated, out of scope.
- No new entitlements, no `Date.now`-dependent formatting assertions (locale/time-fragile tests
  assert non-nil instead of exact strings where locale-dependent).
- The Xcode project uses filesystem-synchronized groups: **new files on disk under
  `QuickNetStats/` or `QuickNetStatsTests/` join their targets automatically — do not edit
  `project.pbxproj`.** Note the intentional "Camponents" spelling.
- **NEVER commit** — the user commits explicitly (CLAUDE.md Git Policy). Branch is already
  `feat/detailed-info-dropdown`.
- Build/test via the Xcode MCP bridge helper (Xcode must stay open on the project;
  `tabIdentifier` is `windowtab1`):
  ```bash
  # Build
  python3 /Users/federicoimberti/.claude/jobs/6e62f175/tmp/xcode_mcp.py call BuildProject '{"tabIdentifier":"windowtab1"}'
  # All tests (fast, ~30 s for 110 tests)
  python3 /Users/federicoimberti/.claude/jobs/6e62f175/tmp/xcode_mcp.py call RunAllTests '{"tabIdentifier":"windowtab1"}'
  ```
  CLI fallback if the bridge fails:
  ```bash
  env DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer xcodebuild test \
    -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'
  ```
- SourceKit "No such module 'Testing'" diagnostics in the editor are stale-indexer noise; trust
  the build/test runs only.
- Lint at the end: `env DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swiftlint lint`
  (config `.swiftlint.yml`; `trailing_whitespace`/`opening_brace` disabled).

### Task 1: `ConnectionDetails` model, rows, formatting

**Files:**
- Create: `QuickNetStats/Models/ConnectionDetails.swift`
- Test: `QuickNetStatsTests/ConnectionDetailsTests.swift`

**Produces (later tasks consume exactly these):**

```swift
struct DetailRow: Identifiable, Equatable {
    let label: String
    let value: String
    var id: String { label }
}

struct ConnectionDetails: Equatable {
    struct Interface: Equatable {
        var bsdName: String?
        var displayName: String?
        var macAddress: String?
        var mtu: Int?
        var linkSpeedMbps: Double?
    }
    struct Addressing: Equatable {
        var ipv6Address: String?
        var publicIPv6: String?
        var subnetMask: String?
        var routerAddress: String?
        var hostname: String?
    }
    struct DnsDhcp: Equatable {
        var dnsServers: [String] = []
        var searchDomains: [String] = []
        var dhcpLeaseExpiry: Date?
    }
    struct Wifi: Equatable {
        var channelNumber: Int?
        var band: String?          // "2.4 GHz" | "5 GHz" | "6 GHz"
        var channelWidthMHz: Int?
        var phyMode: String?       // "802.11ax"
        var security: String?      // "WPA3 Personal"
        var countryCode: String?
    }
    var interface: Interface
    var addressing: Addressing
    var dnsDhcp: DnsDhcp
    var wifi: Wifi?

    var interfaceRows: [DetailRow]   // nil fields omitted
    var addressingRows: [DetailRow]
    var dnsDhcpRows: [DetailRow]
    var wifiRows: [DetailRow]        // [] when wifi == nil

    static let mockWifi: ConnectionDetails      // fully populated, wifi != nil
    static let mockEthernet: ConnectionDetails  // wifi == nil, link speed 1000
    static let mockVPN: ConnectionDetails       // only router/DNS/hostname populated
}
```

Row content rules (test each):
- Interface "Name": `displayName (bsdName)` → "Wi-Fi (en0)"; only one present → that one; both nil → row omitted.
- "Link speed": `< 1000` → "866 Mbps" (no decimals); `>= 1000` → "1 Gbps"/"2.5 Gbps" (trailing `.0` stripped). From `linkSpeedMbps`.
- "Channel": "44 · 5 GHz · 80 MHz" — pieces with nil dropped ("44 · 5 GHz" if width nil); all nil → row omitted.
- "DNS servers"/"Search domains": comma-joined; empty array → row omitted.
- "DHCP lease expires": `dhcpLeaseExpiry.formatted(date: .abbreviated, time: .shortened)` — test asserts row present for a date, absent for nil (no exact-string assert; locale-dependent).
- Rows keep design order (see table in Design). Empty group → `[]`.

- [x] **Step 1**: Invoke swift-testing-expert skill, then write `ConnectionDetailsTests` covering: each group's nil-omission per row, name-row composition (3 variants), link-speed formatting ("866 Mbps", "1 Gbps", "2.5 Gbps"), channel-text composition (full, partial, omitted), DNS join, `wifiRows` empty when `wifi == nil`, mocks non-empty.
- [x] **Step 2**: Run tests → expect **compile failure** (types don't exist) via RunAllTests.
- [x] **Step 3**: Implement `ConnectionDetails.swift` (model + row builders + private formatters + mocks).
- [x] **Step 4**: RunAllTests → all pass (110 + new).

### Task 2: `LiveConnectionStats` model + rate formatting

**Files:**
- Create: `QuickNetStats/Models/LiveConnectionStats.swift`
- Test: `QuickNetStatsTests/LiveConnectionStatsTests.swift`

**Produces:**

```swift
struct LiveConnectionStats: Equatable {
    var downloadBytesPerSec: Double?
    var uploadBytesPerSec: Double?
    var rssiDBm: Int?
    var noiseDBm: Int?
    var txRateMbps: Double?

    var snrDB: Int? // rssi − noise when both present
    var rssiText: String?      // "-52 dBm"
    var noiseText: String?     // "-95 dBm"
    var snrText: String?       // "43 dB"
    var txRateText: String?    // "866 Mbps" (reuse Task 1 formatter — make it internal static)
    var downloadText: String?  // via rateText
    var uploadText: String?

    static func rateText(_ bytesPerSec: Double) -> String
    // < 1_000 → "999 B/s"; < 1_000_000 → "12.3 KB/s"; < 1_000_000_000 → "1.2 MB/s"; else "1.2 GB/s"
    // one decimal for KB and above, no decimals for B/s; deterministic (no locale formatter)

    static let mockLiveWifi: LiveConnectionStats   // all fields
    static let mockLiveWired: LiveConnectionStats  // throughput only
}
```

- [x] **Step 1**: Write failing tests: `snrDB` math (−52, −95 → 43; nil when either missing), each `*Text` (exact strings — deterministic formatter), `rateText` at boundaries (999, 1_000, 999_999, 1_000_000, 1_500_000_000), mocks.
- [x] **Step 2**: RunAllTests → compile failure.
- [x] **Step 3**: Implement.
- [x] **Step 4**: RunAllTests → green.

### Task 3: `SystemConfigReader`

**Files:**
- Create: `QuickNetStats/Managers/SystemConfigReader.swift`
- Test: `QuickNetStatsTests/ConnectionReadersTests.swift` (shared by Tasks 3–5)

**Produces:**

```swift
struct SystemConfigSnapshot: Equatable {
    var primaryInterface: String?
    var primaryInterfaceDisplayName: String?
    var primaryService: String?
    var routerAddress: String?
    var dnsServers: [String] = []
    var searchDomains: [String] = []
    var subnetMask: String?
    var dhcpLeaseExpiry: Date?
    var hostname: String?
}
protocol SystemConfigReading { func snapshot() -> SystemConfigSnapshot }
struct SystemConfigReader: SystemConfigReading { ... }
```

Implementation (SCDynamicStore reads, all optional-safe):
- `SCDynamicStoreCreate(nil, "QuickNetStats" as CFString, nil, nil)`
- `State:/Network/Global/IPv4` → `Router`, `PrimaryInterface`, `PrimaryService`
- `State:/Network/Global/DNS` → `ServerAddresses`, `SearchDomains`
- `State:/Network/Service/<PrimaryService>/IPv4` → `SubnetMasks.first`
- `SCDynamicStoreCopyDHCPInfo(store, service as CFString)` → prefer
  `DHCPInfoGetLeaseExpirationTime`; if that symbol is unavailable in the SDK, compute
  `DHCPInfoGetLeaseStartTime` + option 51 (`DHCPInfoGetOptionData(info, 51)`, 4-byte big-endian
  seconds). Verify against a real run.
- `SCDynamicStoreCopyLocalHostName(store)` → hostname
- Display name: `SCNetworkInterfaceCopyAll()`, match `SCNetworkInterfaceGetBSDName` ==
  primaryInterface → `SCNetworkInterfaceGetLocalizedDisplayName`.

- [x] **Step 1**: Write lenient smoke tests: `snapshot()` returns without crashing; on a connected machine (`NWPathMonitor` not consulted — just assert types) `dnsServers` is an array (may be empty on CI), no force-unwraps reachable. If `primaryInterface != nil`, it matches `^[a-z]+[0-9]+$`.
- [x] **Step 2**: RunAllTests → compile failure.
- [x] **Step 3**: Implement.
- [x] **Step 4**: RunAllTests → green. Manually eyeball one real snapshot via a debug `print` in test output (then remove the print).

### Task 4: `InterfaceReader`

**Files:**
- Create: `QuickNetStats/Managers/InterfaceReader.swift`
- Test: extend `QuickNetStatsTests/ConnectionReadersTests.swift`

**Produces:**

```swift
struct InterfaceSnapshot: Equatable {
    var macAddress: String?      // "aa:bb:cc:dd:ee:ff"
    var mtu: Int?
    var ipv6Address: String?
    var linkSpeedMbps: Double?
    var rxBytes: UInt64?
    var txBytes: UInt64?
}
protocol InterfaceReading { func snapshot(for bsdName: String) -> InterfaceSnapshot }
struct InterfaceReader: InterfaceReading {
    static func preferredIPv6(from candidates: [String]) -> String?
}
```

Implementation notes:
- One `getifaddrs` pass filtered to `bsdName`:
  - `AF_LINK` → `sockaddr_dl` (`withMemoryRebound`) → MAC bytes formatted `%02x:` joined; and
    `ifa_data as if_data` → `ifi_mtu`, `ifi_baudrate` (baud > 0 → `/1_000_000` Mbps).
  - `AF_INET6` → `getnameinfo(NI_NUMERICHOST)` (same pattern as
    `NetworkDetailsManager.getPrivateIPAddress`), strip any `%scope` suffix, collect candidates.
- `preferredIPv6` (pure, TDD): global unicast first (not `fe80`-prefixed, not `fc`/`fd`), else
  ULA (`fc`/`fd`), never link-local. Case-insensitive.
- Counters: `sysctl` MIB `[CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]`, walk `if_msghdr`
  records by `ifm_msglen`, on `ifm_type == RTM_IFINFO2` decode `if_msghdr2`
  (use `loadUnaligned`), match `ifm_index == if_nametoindex(bsdName)` →
  `ifm_data.ifi_ibytes` / `ifi_obytes` (64-bit).

- [x] **Step 1**: Write failing tests — `preferredIPv6`: `(["fe80::1", "2a00:1::2", "fd12::1"]) == "2a00:1::2"`, `(["fe80::1", "fd12::1"]) == "fd12::1"`, `(["FE80::1"]) == nil`, `([]) == nil`. Smoke: `snapshot(for: "lo0")` doesn't crash and `mtu != nil`; `snapshot(for: "definitely-not-real99")` returns all-nil snapshot; if the machine has an `en0`, counters are non-nil.
- [x] **Step 2**: RunAllTests → compile failure.
- [x] **Step 3**: Implement.
- [x] **Step 4**: RunAllTests → green.

### Task 5: `WifiReader`

**Files:**
- Create: `QuickNetStats/Managers/WifiReader.swift` (the ONLY file importing CoreWLAN)
- Test: extend `QuickNetStatsTests/ConnectionReadersTests.swift`

**Produces:**

```swift
struct WifiSnapshot: Equatable {
    var channelNumber: Int?
    var band: String?
    var channelWidthMHz: Int?
    var phyMode: String?
    var security: String?
    var countryCode: String?
    var rssiDBm: Int?
    var noiseDBm: Int?
    var txRateMbps: Double?
}
protocol WifiReading { func snapshot(for bsdName: String) -> WifiSnapshot? }
struct WifiReader: WifiReading { ... }
```

Implementation notes:
- `CWWiFiClient.shared().interface(withName: bsdName)` — nil (non-Wi-Fi BSD name / no Wi-Fi) → return nil. **Never touch `ssid()`/`bssid()`.**
- `wlanChannel()` → number; band switch (`.band2GHz`→"2.4 GHz", `.band5GHz`→"5 GHz", `.band6GHz`→"6 GHz"); width switch (20/40/80/160 MHz), `@unknown default` → nil.
- `activePHYMode()` switch → "802.11a/b/g/n/ac/ax"; `.none`/unknown → nil.
- `security()` switch → "Open", "WEP", "WPA Personal", "WPA2 Personal", "WPA3 Personal", "WPA2/WPA3 Personal" (transition), enterprise variants, unknown → nil.
- `rssiValue()`/`noiseMeasurement()` return 0 when unavailable → map 0 to nil; `transmitRate()` ≤ 0 → nil.

- [x] **Step 1**: Write lenient smoke tests: `snapshot(for: "lo0") == nil`; on this machine `snapshot(for: "en0")` (Wi-Fi here) either nil (Wi-Fi off) or has `rssiDBm` in −100...0 when non-nil. Grep-style guard test: source of `WifiReader.swift` contains neither `ssid(` nor `bssid(` (read file from `#filePath`-relative path… if fragile, drop this and rely on review).
- [x] **Step 2**: RunAllTests → compile failure.
- [x] **Step 3**: Implement.
- [x] **Step 4**: RunAllTests → green.

### Task 6: `ConnectionDetailsManager` — fetch path

**Files:**
- Create: `QuickNetStats/Managers/ConnectionDetailsManager.swift`
- Test: `QuickNetStatsTests/ConnectionDetailsManagerTests.swift`

**Consumes:** all three protocols + snapshots (Tasks 3–5), models (Tasks 1–2).
**Produces:**

```swift
class ConnectionDetailsManager: ObservableObject {
    @Published private(set) var details: ConnectionDetails?
    @Published private(set) var liveStats: LiveConnectionStats?
    @Published private(set) var isLive = false

    init(systemConfig: SystemConfigReading = SystemConfigReader(),
         interfaceReader: InterfaceReading = InterfaceReader(),
         wifiReader: WifiReading = WifiReader(),
         session: URLSession = .reachabilitySession,
         pollInterval: TimeInterval = 1.0)

    func fetchDetails() async
    func refresh() async          // no-op when details == nil
    func startLive()
    func stopLive()
    static func bytesPerSecond(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double?
}
```

Fetch assembly: `systemConfig.snapshot()` → primary BSD name → `interfaceReader.snapshot(for:)`
+ `wifiReader.snapshot(for:)` (nil ⇒ `wifi` group nil); `async let` public IPv6 from
`https://api6.ipify.org` (2xx + response body contains ":" else nil — mirror
`NetworkDetailsManager.fetchPublicIpAddress` incl. the status-code guard); assemble
`ConnectionDetails` and publish once at the end. No primary interface ⇒ still publish
(router/DNS/hostname may exist; interface group rows mostly omitted).

Test doubles (in the test file): `MockSystemConfigReader`/`MockInterfaceReader`/`MockWifiReader`
structs wrapping stub snapshots, plus `MockURLProtocol` sessions — copy the private
`mockSession()` helper pattern from `NetworkDetailsManagerTests` (token-keyed handlers already
exist in the shared `MockURLProtocol`).

- [x] **Step 1**: Invoke swift-testing-expert (if context lost), write failing tests: fetch assembles all four groups from stubs; wifi reader nil → `details?.wifi == nil`; ipify 200 "2a00::1" → `publicIPv6 == "2a00::1"`; ipify 500 or error → nil; response without ":" → nil; no primary interface → details still published with router/DNS; `refresh()` before any fetch → `details` stays nil (stub readers record zero calls); `refresh()` after fetch → readers called again.
- [x] **Step 2**: RunAllTests → compile failure.
- [x] **Step 3**: Implement fetch path only (`startLive`/`stopLive` empty stubs, `bytesPerSecond` unimplemented `nil`).
- [x] **Step 4**: RunAllTests → green (live tests come next task).

### Task 7: `ConnectionDetailsManager` — live polling

**Files:**
- Modify: `QuickNetStats/Managers/ConnectionDetailsManager.swift`
- Test: extend `QuickNetStatsTests/ConnectionDetailsManagerTests.swift`

Implementation:
- `bytesPerSecond`: `elapsed > 0 && current >= previous` else nil; `Double(current - previous) / elapsed`.
- Private `previousSample: (rx: UInt64, tx: UInt64, at: Date)?`, cleared by `startLive()` and `stopLive()`.
- `startLive()`: guard `!isLive`; `isLive = true`; store `liveTask = Task { [weak self] in while !Task.isCancelled { guard let self else { return }; self.tick(); try? await Task.sleep(for: .seconds(self.pollInterval)) } }` (pattern from `NetworkStatsManager` polling).
- `tick()`: guard `let bsd = details?.interface.bsdName` else return; read interface + wifi snapshots; throughput from `previousSample` via `bytesPerSecond` (nil on first tick); update `previousSample`; publish `LiveConnectionStats` (RF fields straight from wifi snapshot).
- `stopLive()`: cancel + nil task, `isLive = false`, `liveStats = nil`, `previousSample = nil`.
- `deinit`: `liveTask?.cancel()`.

- [x] **Step 1**: Write failing tests (inject `pollInterval: 0.05`; reuse/introduce a small
  `eventually(timeout:condition:)` async helper — check `NetworkStatsManagerTests` for an
  existing one first):
  - `bytesPerSecond` math: `(1_000, 3_000, 2.0) == 1_000`; negative delta → nil; `elapsed 0` → nil.
  - After fetch + `startLive()`: eventually `liveStats?.rssiDBm == stub value`; eventually (second tick, counters stub +1_000 per call via a mutating stub) `downloadBytesPerSec != nil`.
  - First tick: `downloadBytesPerSec == nil` while `rssiDBm != nil`.
  - `startLive()` without fetch → no crash, `liveStats` stays nil-throughput (tick guards).
  - `stopLive()` → `isLive == false`, `liveStats == nil`; double `startLive()` doesn't stack tasks (poll count from stub call-counting stays plausible).
- [x] **Step 2**: RunAllTests → failures on new tests.
- [x] **Step 3**: Implement.
- [x] **Step 4**: RunAllTests → green.

### Task 8: `DetailGroupView`

**Files:**
- Create: `QuickNetStats/Views/Camponents/DetailGroupView.swift`

**Consumes:** `DetailRow` (Task 1).

- [x] **Step 1**: Invoke swiftui-expert skill (if context lost). Implement:

```swift
struct DetailGroupView: View {
    let title: String
    let rows: [DetailRow]

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.leading)
                            Button {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(row.value, forType: .string)
                            } label: {
                                Text(row.value)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .buttonStyle(.plain)
                            .help("Click to copy")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

  Previews: one populated group (use `ConnectionDetails.mockWifi.interfaceRows`), one empty
  (renders nothing), one with a long IPv6 value (truncation visible).
- [x] **Step 2**: BuildProject → succeeds; visually check previews render (RenderPreview via
  bridge if convenient, else rely on build + later manual run).

### Task 9: `LiveStatsSectionView`

**Files:**
- Create: `QuickNetStats/Views/Camponents/LiveStatsSectionView.swift`

**Consumes:** `LiveConnectionStats` (Task 2).

- [x] **Step 1**: Implement. Inputs: `let isLive: Bool`, `let showsWifiRows: Bool`,
  `let stats: LiveConnectionStats?`, `let onToggle: () -> Void`. Layout: caption row
  (`Text("Live")` caption style + `Spacer` + toggle `Button(isLive ? "Stop" : "Live")` with
  `waveform`-family SF Symbol, `.buttonStyle(.plain)`, `.focusable(false)`); then the same
  `Grid` shape as `DetailGroupView` with fixed rows: Download, Upload always; RSSI, Noise, SNR,
  Tx rate when `showsWifiRows`. Values: when `!isLive` → "—" for all and the whole grid
  `.foregroundStyle(.tertiary)`; when live → `stats?.downloadText ?? "—"` etc. Live rows are
  NOT copy buttons (values churn every second) — plain `Text`.
  Previews: idle wifi, live wifi (`mockLiveWifi`), live wired (`mockLiveWired`, no RF rows).
- [x] **Step 2**: BuildProject → succeeds.

### Task 10: `ConnectionDetailsView` + wiring

**Files:**
- Create: `QuickNetStats/Views/NetStatsView/ConnectionDetailsView.swift`
- Modify: `QuickNetStats/QuickNetStatsApp.swift` (third `@StateObject`, pass to `ContentView`)
- Modify: `QuickNetStats/Views/ContentView.swift` (accept + forward manager; refresh button adds `await connectionDetailsManager.refresh()`)
- Modify: `QuickNetStats/Views/NetStatsView/NetStatsView.swift` (accept manager, insert view after `ipButtonsSection` inside the `if vm.netStats.isConnected` gate — add that gate around the new view only; update ALL previews)

**Consumes:** manager (Tasks 6–7), views (Tasks 8–9).

- [x] **Step 1**: Implement `ConnectionDetailsView`:

```swift
struct ConnectionDetailsView: View {
    @ObservedObject var manager: ConnectionDetailsManager
    @EnvironmentObject var settings: Settings
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
                if !isExpanded { manager.stopLive() }
            } label: {
                HStack(spacing: 6) {
                    Text("Connection Details")
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)

            if isExpanded {
                if let details = manager.details {
                    DetailGroupView(title: "Interface", rows: details.interfaceRows)
                    DetailGroupView(title: "Addressing", rows: details.addressingRows)
                    DetailGroupView(title: "DNS & DHCP", rows: details.dnsDhcpRows)
                    DetailGroupView(title: "Wi-Fi", rows: details.wifiRows)
                    LiveStatsSectionView(
                        isLive: manager.isLive,
                        showsWifiRows: details.wifi != nil,
                        stats: manager.liveStats,
                        onToggle: { manager.isLive ? manager.stopLive() : manager.startLive() }
                    )
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .animation(settings.useAnimations ? .default : nil, value: isExpanded)
        .task(id: isExpanded) {
            if isExpanded && manager.details == nil { await manager.fetchDetails() }
        }
        .onDisappear { manager.stopLive() }
    }
}
```

  Verify during implementation that `onDisappear` fires when the `.window` MenuBarExtra closes
  (log once, run app); if it does not, observe `NSWindow.willCloseNotification` instead — note
  outcome in this file.
  Previews for `ConnectionDetailsView` and updated `NetStatsView` previews: build a
  `ConnectionDetailsManager.preview(details:)` static in an `#if DEBUG` extension (stub readers
  returning mock-derived snapshots) — follow `NetworkStats.mock*` naming conventions.
- [x] **Step 2**: BuildProject → succeeds.
- [x] **Step 3**: RunAllTests → full suite green.
- [x] **Step 4**: Launch the app (Debug build product via `open`), manually verify: expand →
  values appear; press Live → values tick; close popover → reopen → collapsed and idle;
  Ethernet/Wi-Fi variants as available; refresh button re-fetches. Report observations.
  (See Implementation Notes — headless environment blocked interactive verification.)

### Task 11: Final verification

- [x] **Step 1**: `swiftlint lint` (with `DEVELOPER_DIR`) → 0 violations (run `--fix` first if needed).
- [x] **Step 2**: RunAllTests → full suite green; BuildProject Release config not required (CI covers release at tag time).
- [x] **Step 3**: Re-read this plan's Design section and confirm every group/row/behavior is
  implemented or explicitly noted; update checkboxes; list any deviations at the end of this file.
- [x] **Step 4**: Code-review checkpoint — performed from the main session (subagent dispatch),
  not by the implementing agent. Verdict 2026-07-04: *ready to merge with fixes* — no Critical
  findings; the two Important findings plus one recommended Minor were fixed and re-verified
  (167/167 tests, lint 0). See "Code-review fixes" in the Implementation Notes below.

---

## Implementation Notes (deviations & observations)

### Task 3 — SystemConfigReader

- **DHCP lease API:** `DHCPInfoGetLeaseExpirationTime` compiled cleanly (macOS 10.8+), returning a
  `CFDate?` that bridges directly to `Date?` (CF implicit bridging is enabled in the header). The
  option-51 fallback described in the plan was **not needed**.
- **Required submodule import:** `SCDynamicStoreCopyDHCPInfo` / `DHCPInfoGetLeaseExpirationTime`
  are NOT re-exported by the `SystemConfiguration` umbrella. They live in an explicit submodule and
  need `import SystemConfiguration.SCDynamicStoreCopyDHCPInfo` — a plain `import SystemConfiguration`
  gives "Cannot find 'SCDynamicStoreCopyDHCPInfo' in scope".
- **Real-machine snapshot (this dev machine):** primaryInterface `en1`, displayName "Wi-Fi",
  router `10.0.0.1`, DNS `["100.100.100.100", "fd7a:115c:a1e0::53"]` (Tailscale MagicDNS active),
  searchDomains `["dhole-tritone.ts.net"]`, subnetMask `255.255.255.0`, hostname "Eurydice".
  `dhcpLeaseExpiry` was **nil** here (network/Tailscale doesn't expose a lease on the primary
  service) — confirms the nil-lease → row-omitted path works without crashing. Note the primary
  interface is `en1` (not `en0`) on this machine because of an active VPN/Tailscale setup.

### Task 4 — InterfaceReader

- `MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)` compiles and returns a valid offset, so the
  MAC address is read from the raw allocation rather than trusting the declared 12-byte `sdl_data`
  tuple size (robust for interface names of any length).
- `UnsafeRawPointer.loadUnaligned(as:)` is available on the macOS 13 target (Swift stdlib 5.7) and
  is used to walk the `NET_RT_IFLIST2` `if_msghdr`/`if_msghdr2` records.
- `lo0` reports MTU and non-nil 64-bit byte counters (loopback has an IFLIST2 record); a bogus
  interface name yields an all-nil `InterfaceSnapshot` (index lookup + getifaddrs both miss).

### Task 5 — WifiReader

- **CoreWLAN enum mapping via `rawValue`, not case names.** The Swift-imported `CWSecurity` cases
  have fragile acronym casing (`.WEP`, `.OWE` vs `.wpaPersonal`), so all four enums (`CWChannelBand`,
  `CWChannelWidth`, `CWPHYMode`, `CWSecurity`) are mapped by their documented, ABI-stable integer
  raw values with a `default: nil` catch-all. This compiled first try and needs no extra enum-case
  mapping. `CWSecurity` includes `Personal` (5), `Enterprise` (10), and the `WPA3Transition` (13,
  shown as "WPA2/WPA3 Personal") and OWE (14/15) cases; `kCWSecurityUnknown` (NSIntegerMax) → nil.
- Interface accessors are methods in Swift: `wlanChannel()`, `activePHYMode()`, `security()`,
  `rssiValue()`, `noiseMeasurement()`, `transmitRate()`, `countryCode()`; `CWChannel.channelBand`
  /`.channelWidth`/`.channelNumber` are properties. **No `ssid()`/`bssid()` calls anywhere.**

### Tasks 6–7 — ConnectionDetailsManager

- `async let publicIPv6 = fetchPublicIPv6()` compiles under `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor`; the local (synchronous) reader calls run on the main actor and the network I/O
  overlaps at the `await`. Public IPv6 guard mirrors `NetworkDetailsManager`: 2xx status AND the
  body must contain a colon, else nil.
- `deinit { liveTask?.cancel() }` compiles fine accessing the main-actor stored property — same
  pattern the existing `NetworkStatsManager.deinit` already uses (approachable-concurrency /
  isolated deinit is permitted in this project).
- The poll loop mirrors `NetworkStatsManager.pollingTask`: `Task { [weak self] in while
  !Task.isCancelled { guard let self else { return }; self.tick(); try? await Task.sleep(...) } }`.
  First tick fires immediately (RF only, `previousSample == nil` → nil throughput); throughput
  appears from the second tick. `startLive()` is guarded by `!isLive` so a double call cannot stack
  a second loop.
- Live tests use a private `eventually(timeout:_:)` main-actor helper (10 ms poll, 3 s default
  timeout) — no existing async-wait helper was found in `NetworkStatsManagerTests` (those tests are
  synchronous), so this one was introduced. The `MockInterfaceReader.incrementPerCall` knob grows
  the byte counters each call to drive a deterministic positive throughput delta.

### Task 10 — ConnectionDetailsView, wiring, and manual-run limitation

- Wiring completed: `QuickNetStatsApp` owns a third `@StateObject connectionDetailsManager`, passed
  through `ContentView` → `NetStatsView`; the refresh button now also `await`s
  `connectionDetailsManager.refresh()` (a no-op until the dropdown has been opened once). The
  dropdown is gated by `if vm.netStats.isConnected` inside `NetStatsView.body`, directly after
  `ipButtonsSection`. All `NetStatsView` previews were updated with the new required parameter via
  a new `#if DEBUG ConnectionDetailsManager.preview(details:isLive:liveStats:)` factory (sets the
  private(set) published state directly from the same file; readers never run in previews).
- **`onDisappear` NOT verified at runtime.** The build environment is headless: the app launches
  cleanly (Debug product, bundle id `com.federicoimberti.quicknetstats.dev`, process stays alive),
  but macOS UI-automation (System Events / AppleScript) is not permitted here, so I could not click
  the `.window`-style `MenuBarExtra` item to open the popover, expand the dropdown, toggle Live, or
  close the popover. Temporary `NSLog("QNS_DEBUG …")` markers were added to `onDisappear`,
  `.task`/fetch, `startLive`, and `stopLive`, and a unified-log stream was captured while attempting
  scripted clicks; the clicks never registered (permission-blocked) so no markers were emitted. The
  debug logging has been removed and the project rebuilt clean.
  - **What IS verified:** clean Debug + test build; 167/167 unit tests green, covering the logic
    behind every UI action — fetch assembly (all 4 groups, public-IPv6 success/failure), live-poll
    start/stop/first-tick-RF/second-tick-throughput, `bytesPerSecond` math, and `refresh()` gating.
    Readers were exercised on real hardware (Task 3 eyeball). `onDisappear { manager.stopLive() }`
    is wired as specified.
  - **What remains for a human/local check:** confirm `onDisappear` actually fires when the
    `.window` MenuBarExtra popover closes (design's open question). If it turns out not to fire on
    this macOS, the documented fallback is to observe `NSWindow.willCloseNotification`. Also
    visually confirm dropdown rendering, live values ticking, and collapsed-on-reopen behavior.

### Task 11 — Final verification & consolidated deviations

- `swiftlint lint` → **0 violations, 0 serious** across 35 files. Two warnings surfaced during
  implementation and were fixed (not suppressed): the 3-member `previousSample` tuple (`large_tuple`)
  became a private `ByteSample` struct, and `WifiReader.securityText`'s 16-case switch
  (`cyclomatic_complexity` 17) became a `[Int: String]` dictionary lookup.
- Full suite: **167/167 pass** (baseline 110 → +57 new). New test files: `ConnectionDetailsTests`
  (22), `LiveConnectionStatsTests` (13), `ConnectionReadersTests` (SystemConfig 2, Interface 3,
  Wifi 2), `ConnectionDetailsManagerTests` (fetch 9 + live 6).

**Design coverage:** every model field, reader, manager API, view, group/row (Interface, Addressing,
DNS & DHCP, Wi-Fi), the Live section, and all three wiring points are implemented as specified.

**Deviations from the plan (all intentional, all keep the design's intent):**

1. **DHCP lease API** — used `DHCPInfoGetLeaseExpirationTime` directly (the plan's preferred path);
   the option-51 fallback was unnecessary. Required the explicit
   `import SystemConfiguration.SCDynamicStoreCopyDHCPInfo` submodule import.
2. **CoreWLAN enum mapping** — mapped `CWChannelBand`/`CWChannelWidth`/`CWPHYMode`/`CWSecurity` by
   ABI-stable `rawValue` integers with a `default`/absent → nil, instead of Swift enum-case switches
   with `@unknown default`. Same guarantee (unknown/future → row omitted, no crash) without the
   fragile Swift acronym-case casing (`.WEP`/`.OWE`).
3. **Lint-driven refactors** — `securityText` is a dictionary (not a switch); `previousSample` is a
   `ByteSample` struct (not the literal `(rx:tx:at:)` tuple). Behavior identical.
4. **WifiReader smoke test** — iterates `["en0","en1"]` rather than assuming `en0` (this machine's
   Wi-Fi is `en1`); the fragile `#filePath` source-grep guard for `ssid(`/`bssid(` was dropped per
   the plan's own escape hatch — the guarantee is upheld by never writing those calls (verifiable by
   review) and is documented in `WifiReader.swift`.
5. **Task 10 Step 4 manual run** — could not be performed interactively (headless env blocks UI
   automation); see the Task 10 note above for exactly what was and was not verified.

### Code-review fixes (2026-07-04, post-review)

- **Important — `InterfaceReader.byteCounters`**: the sysctl `NET_RT_IFLIST2` walk now bounds-checks
  every `loadUnaligned` (`offset + size(if_msghdr) <= length` loop condition; `if_msghdr2` load
  additionally guarded by buffer bound and `ifm_msglen`). The MAC read in `readLinkLayer` guards
  `sdl_data + sdl_nlen + 6 <= sdl_len`. Defense-in-depth against truncated/inconsistent
  kernel-sourced records — previously a potential buffer over-read.
- **Important — `firstTickHasRFOnly` test**: poll interval raised 0.3 s → 60 s so the second tick
  can never race the assertion under CI load; `stopLive()` cancels the sleep so the test stays fast.
- **Minor (recommended) — `ConnectionDetailsManager.fetchDetails`**: publishes nothing when the
  task was cancelled (popover closed mid-expand), so the next expand retries instead of keeping a
  half-fetched snapshot with a silently missing public-IPv6 row.
- Remaining review findings left intentionally: `@ObservedObject` → `let` in the two pass-through
  views (energy micro-optimization), `.help` full-value tooltip vs "Click to copy" (plan-internal
  conflict — current code shows "Click to copy"), no `deinit`-cancels test (impractical under
  main-actor isolation; leak impossible by construction), duplicated 3-line pasteboard idiom.
- Human verification 2026-07-04: **`onDisappear` confirmed to fire** when the `.window`
  MenuBarExtra popover closes — the Live loop stops on close as designed; the
  `NSWindow.willCloseNotification` fallback is not needed. Federico also applied some UI
  adjustments by hand before the initial commit.
