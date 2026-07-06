# Plan: Expand Connection Details Coverage

> **Date**: 2026-07-06
> **Scope**: Surface the remaining information obtainable from the APIs the app already uses —
> proxies, IPv6 router, IPv4 config method, DHCP server/lease start, computer name, broadcast
> address, Ethernet media, error/drop/packet counters, Wi-Fi tx power + interface mode, and
> NWPath capability flags + other available interfaces. Everything except reverse DNS (excluded
> by decision).
> **Prerequisite**: The Connection Details dropdown
> (`context/planning/add-connection-details-dropdown.md`), shipped in 3.0.0 betas.

---

## Context

An API-coverage audit found that the four sources the dropdown already taps (SCDynamicStore,
getifaddrs/sysctl, CoreWLAN, NWPath) expose substantially more than we present. All items below
are sandbox-safe, prompt-free, and macOS-13-safe. SSID/BSSID remain out of scope
(location-gated); reverse DNS of the public IP was considered and excluded.

The "maximal inclusion" principle from the parent plan still governs: prefer adding a field;
nil values omit their row; empty groups vanish.

---

## Overview

```
ConnectionDetailsManager.fetchDetails()
 ├─ SystemConfigReader   +proxies +ipv6Router +ipv4ConfigMethod +dhcpServer +leaseStart +computerName
 ├─ InterfaceReader      +broadcast +mediaDescription +packet/error/drop counters (live)
 ├─ WifiReader           +txPowerMw +interfaceMode
 ├─ PathReader (NEW)     supportsIPv4/IPv6/DNS + other available interfaces   (one-shot NWPathMonitor)
 └─ URLSession           (unchanged)

Dropdown groups after this change:
  Interface   : Name, MAC, MTU, Link speed, +Media (Ethernet), +Supports, +Also available
  Addressing  : Router, +Router (IPv6), Subnet mask, +Broadcast, IPv6, Public IPv6,
                +IPv4 config, Hostname, +Computer name
  DNS & DHCP  : DNS servers, Search domains, +DHCP server, +Lease started, Lease expires
  Proxy (NEW) : +HTTP, +HTTPS, +SOCKS        (group renders only when at least one is active)
  Wi-Fi       : Channel, PHY mode, Generation, +Mode, +Tx power, Security, Country code
  Live        : Download, Upload, +Packets ↓, +Packets ↑, +Errors, +Drops, RSSI, Noise, SNR, Tx rate
```

---

## Design

### `SystemConfigSnapshot` / `SystemConfigReader` additions

- `proxies: ProxySnapshot` from `SCDynamicStoreCopyProxies(store)`: for each of HTTP/HTTPS/SOCKS,
  when the corresponding `*Enable` key is 1, capture `"host:port"` (`kSCPropNetProxiesHTTPProxy` +
  `...HTTPPort`, etc.). Struct with three `String?` fields.
- `ipv6Router: String?` — `State:/Network/Global/IPv6 → Router` (next to the IPv4 key we read).
- `ipv4ConfigMethod: String?` — per-primary-service `ConfigMethod` ("DHCP", "Manual",
  "LinkLocal"…). Try `Setup:/Network/Service/<id>/IPv4` first, fall back to
  `State:/Network/Service/<id>/IPv4`; record which domain worked in the Implementation Notes.
- `dhcpServer: String?` — DHCP option 54 (4-byte IPv4) from the `SCDynamicStoreCopyDHCPInfo`
  blob we already parse for the lease.
- `dhcpLeaseStart: Date?` — `DHCPInfoGetLeaseStartTime` (already read internally to compute
  expiry; now surfaced).
- `computerName: String?` — `SCDynamicStoreCopyComputerName(store, nil)`.

### `InterfaceSnapshot` / `InterfaceReader` additions

- `broadcastAddress: String?` — from the `AF_INET` entry's `ifa_dstaddr` (on Darwin this union
  member holds the broadcast address for `IFF_BROADCAST` interfaces; guard the flag and nil).
- `mediaDescription: String?` — `ioctl(SIOCGIFMEDIA)` on a throwaway `socket(AF_INET, SOCK_DGRAM, 0)`
  with `ifmediareq`; map common `ifm_active` subtypes (10baseT/UTP, 100baseTX, 1000baseT,
  2500baseT, 5000baseT, 10GbaseT) plus full/half duplex from the option bits →
  e.g. "1000baseT full-duplex". Unknown subtype or non-Ethernet media → nil. Only meaningful for
  wired interfaces; Wi-Fi typically reports none of these subtypes and degrades to nil naturally.
- Extended counters from the **same** `if_msghdr2.ifm_data` (`if_data64`) we already decode:
  `rxPackets`, `txPackets` (`ifi_ipackets/opackets`), `inErrors`, `outErrors`
  (`ifi_ierrors/oerrors`), `drops` (`ifi_iqdrops`) — all `UInt64?`, same bounds-checked walk.

### `WifiSnapshot` / `WifiReader` additions

- `txPowerMw: Int?` — `transmitPower()`; `<= 0` → nil.
- `interfaceMode: String?` — `interfaceMode()` mapped by rawValue (1 → "Station", 2 → "IBSS",
  3 → "Host AP"; 0/unknown → nil), consistent with the existing rawValue-mapping style.
- `powerOn()`/`serviceActive()` deliberately **not** surfaced: whenever the Wi-Fi group renders
  at all (Wi-Fi is the primary interface), they are constant-true — noise by construction.

### `PathReader` (new, `QuickNetStats/Managers/PathReader.swift`)

The dropdown's manager has no access to `NetworkStatsManager`'s NWPath, and coupling them would
break the self-contained reader architecture. Instead: a fourth protocol-seamed reader.

```swift
struct PathSnapshot: Equatable {
    var supportsIPv4: Bool?
    var supportsIPv6: Bool?
    var supportsDNS: Bool?
    /// Other usable interfaces beside the primary, e.g. ["Ethernet (en1)"].
    var otherInterfaces: [String] = []
}
protocol PathReading { func snapshot(excluding primaryBSDName: String?) async -> PathSnapshot }
struct PathReader: PathReading { ... }
```

Implementation: one-shot `NWPathMonitor` — start on a utility queue, `await` the first
`pathUpdateHandler` callback (delivered immediately on start) via a checked continuation with a
`resumed` guard (the handler can fire more than once), then `cancel()`. Timeout guard (~2 s race
via `Task`) returning an empty snapshot so a pathological monitor can never hang `fetchDetails`.
`otherInterfaces` = `path.availableInterfaces` minus the primary BSD name, formatted
"TypeLabel (bsdName)" with the existing interface-type naming ("Wi-Fi", "Ethernet", "Cellular",
"Loopback" excluded entirely, other → "Other").

### Model changes (`ConnectionDetails.swift`, `LiveConnectionStats.swift`)

- `Interface`: `+ mediaDescription: String?`, `+ supports: String?` (pre-formatted
  "IPv4 · IPv6 · DNS" — built by the manager from PathSnapshot; nil when the path reader returned
  all-nil), `+ otherInterfaces: [String]`. New rows: "Media", "Supports", "Also available"
  (comma-joined), appended after "Link speed" in that order.
- `Addressing`: `+ ipv6Router`, `+ broadcastAddress`, `+ ipv4ConfigMethod`, `+ computerName`.
  Row order per the Overview diagram ("Router (IPv6)" directly after "Router", "Broadcast" after
  "Subnet mask", "IPv4 config" after "Public IPv6", "Computer name" last).
- `DnsDhcp`: `+ dhcpServer: String?`, `+ dhcpLeaseStart: Date?`. Rows "DHCP server" and
  "Lease started" before "Lease expires"; same date formatting as expiry.
- New `Proxy` struct: `httpProxy`, `httpsProxy`, `socksProxy: String?` + `proxyRows` ("HTTP",
  "HTTPS", "SOCKS"); all-nil → empty rows → the group never renders (existing convention).
- `Wifi`: `+ mode: String?`, `+ txPowerMw: Int?`. Rows "Mode" (after "Generation") and
  "Tx power" ("100 mW", after "Mode").
- `LiveConnectionStats`: `+ downloadPacketsPerSec`, `+ uploadPacketsPerSec`, `+ errorsPerSec`
  (in+out combined), `+ dropsPerSec` — all `Double?` with a shared integer-rate formatter
  ("1,234/s" → keep it simple: no thousands separator, "1234/s"; sub-1 rates round to nearest
  integer). Mocks updated.
- All mocks (`mockWifi`, `mockEthernet`, `mockVPN`, live mocks) gain representative values;
  `mockVPN` keeps most new fields nil to exercise omission.

### Manager changes (`ConnectionDetailsManager.swift`)

- Init gains `pathReader: PathReading = PathReader()`.
- `fetchDetails()`: `async let` the path snapshot alongside the public-IPv6 fetch; assemble the
  new model fields (including the "supports" string builder — only listed protocols whose flag
  is `true`; all-false → "None"; all-nil → nil).
- `tick()`: `ByteSample` grows into a `CounterSample` (bytes, packets, errors, drops, timestamp);
  per-second rates via the existing `bytesPerSecond` helper (rename NOT required — reuse as-is
  for each counter pair). First-tick semantics unchanged (rates nil until second sample).

### Views

- `ConnectionDetailsView`: insert `DetailGroupView(title: "Proxy", rows: details.proxyRows)`
  between "DNS & DHCP" and "Wi-Fi" (with matching `Divider` handling).
- `LiveStatsSectionView`: four new rows — "Packets ↓", "Packets ↑", "Errors", "Drops" — after
  Upload, before the RF rows; same idle-grayed "—" convention. Packets/errors/drops rows are
  interface-agnostic (always shown, like Download/Upload).
- `DetailGroupView` unchanged (row-driven).

### Testing (Swift Testing, TDD)

- `ConnectionDetailsTests`: row building for every new field (presence, label, value, order,
  omission on nil), proxy-group emptiness, supports-string composition (all/partial/none/nil),
  otherInterfaces join, media row.
- `LiveConnectionStatsTests`: new rate formatters and mocks.
- `ConnectionDetailsManagerTests`: `MockPathReader`; assembly of supports/otherInterfaces;
  extended live tick — packets/errors/drops deltas from mutating stubs, first-tick nil, reuse of
  counter-reset guard.
- `ConnectionReadersTests`: smoke — proxies read doesn't crash and returns a struct;
  `PathReader.snapshot(excluding:)` returns within the timeout on a real monitor (lenient
  asserts); `mediaDescription` for `lo0` is nil; extended counters non-nil for an active `en*`
  interface when present.

---

## Edge Cases & Constraints

- **VPN primary**: proxies may point at the VPN; config method may be absent — all rows degrade
  to omitted. `otherInterfaces` will list the physical interfaces — correct and useful.
- **PathReader hang-proofing**: the one-shot monitor races a ~2 s timeout and returns an empty
  snapshot on loss; `fetchDetails` must never block on it indefinitely.
- **SIOCGIFMEDIA on non-Ethernet**: returns unmapped/none subtypes → nil → row omitted; never an
  error surfaced to UI.
- **Counter deltas**: same negative-delta (reset) and zero-elapsed guards as byte throughput;
  errors/drops usually 0/s — that is a valid, displayed value while live.
- **Proxy ports**: missing port with enabled proxy → show host alone rather than omitting.
- **macOS 13 floor**: all APIs used (SCDynamicStore keys, `SCDynamicStoreCopyProxies`, if_data64
  fields, SIOCGIFMEDIA, CWInterface.transmitPower/interfaceMode, NWPathMonitor) are ≤ macOS 13.
  No new entitlements; no location-gated calls (`ssid()`/`bssid()` remain forbidden).
- **Out of scope**: reverse DNS of the public IP (excluded by decision), SSID/BSSID, radio
  power/service state rows (constant-true when visible), gateway list from NWPath (redundant
  with SCDynamicStore routers).

---

## Implementation Plan

> **For agentic workers:** execute task-by-task with strict TDD (failing tests → run → implement
> → green). Check each box immediately on step completion. Invoke
> `swift-testing-expert:swift-testing-expert` before test work and
> `swiftui-expert:swiftui-expert-skill` before view work. Fill "Implementation Notes" with real
> observations only. **Never `git add`/`commit`/`push`.** Do not edit `project.pbxproj`.
> Build/test: `caffeinate -dims env DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'`
> (plain `xcodebuild` fails; the Mac sleeps mid-run without caffeinate). Baseline: 188/188 green,
> swiftlint 0. SourceKit editor diagnostics are stale-indexer noise.

### Task 1: Model extensions — `ConnectionDetails`

- [x] **Step 1**: Write failing tests: new rows (Media, Supports, Also available, Router (IPv6),
  Broadcast, IPv4 config, Computer name, DHCP server, Lease started, Mode, Tx power), their
  labels/order/omission-on-nil, `proxyRows` (three rows, partial, empty), updated mocks.
- [x] **Step 2**: Test run → expected compile failures.
- [x] **Step 3**: Implement fields, rows, `Proxy` struct, mock updates.
- [x] **Step 4**: Full suite green.

### Task 2: Model extensions — `LiveConnectionStats`

- [x] **Step 1**: Write failing tests: packets/errors/drops fields, integer-rate formatter
  ("1234/s"), text properties, mock updates.
- [x] **Step 2**: Run → fail. **Step 3**: Implement. **Step 4**: Green.

### Task 3: `SystemConfigReader` additions

- [x] **Step 1**: Extend `SystemConfigSnapshot` (proxies, ipv6Router, ipv4ConfigMethod,
  dhcpServer, dhcpLeaseStart, computerName) + lenient smoke tests (no crash; types sane;
  proxies struct returned).
- [x] **Step 2**: Run → fail. **Step 3**: Implement per Design (record the ConfigMethod domain
  that actually worked). **Step 4**: Green; eyeball one real snapshot via test print, then
  remove the print.

### Task 4: `InterfaceReader` additions

- [x] **Step 1**: Extend `InterfaceSnapshot` (broadcastAddress, mediaDescription, rxPackets,
  txPackets, inErrors, outErrors, drops); failing tests for any pure helpers (media subtype
  mapping table) + smoke tests (`lo0` media nil; active `en*` counters non-nil when present).
- [x] **Step 2**: Run → fail. **Step 3**: Implement (SIOCGIFMEDIA ioctl with closed socket
  `defer`-closed; extend the existing bounds-checked `if_msghdr2` decode). **Step 4**: Green.

### Task 5: `WifiReader` additions

- [x] **Step 1**: Extend `WifiSnapshot` (txPowerMw, interfaceMode) + smoke tests.
- [x] **Step 2**: Run → fail. **Step 3**: Implement (rawValue mapping; ≤0 power → nil).
  **Step 4**: Green.

### Task 6: `PathReader` (new)

- [x] **Step 1**: Failing tests: protocol + `MockPathReader` usable; real `PathReader` smoke —
  returns within timeout, `otherInterfaces` excludes the primary and loopback.
- [x] **Step 2**: Run → fail. **Step 3**: Implement one-shot monitor with continuation guard +
  timeout race. **Step 4**: Green.

### Task 7: Manager assembly + live tick

- [x] **Step 1**: Failing tests with mock readers: supports-string builder (all/partial/none/nil),
  otherInterfaces passthrough, proxy passthrough, new fetch assembly; live tick publishes
  packets/errors/drops rates from second tick (mutating stub), first tick nil, reset guard.
- [x] **Step 2**: Run → fail. **Step 3**: Implement (`pathReader` seam, `CounterSample`,
  assembly). **Step 4**: Green.

### Task 8: Views

- [x] **Step 1**: Invoke swiftui-expert. Add Proxy group to `ConnectionDetailsView`; add the four
  Live rows to `LiveStatsSectionView`; update previews (richer mocks flow automatically).
- [x] **Step 2**: Build succeeds; full suite green.

### Task 9: Final verification

- [x] **Step 1**: swiftlint → 0 violations.
- [x] **Step 2**: Full suite green; re-read the Design section and confirm every field/row is
  implemented or its absence noted; record deviations below.

---

## Implementation Notes (deviations & observations)

### Task 3 — SystemConfigReader (real values observed via throwaway diagnostic, now removed)

- **ConfigMethod domain**: the `Setup:` domain served it (`Setup ConfigMethod=DHCP`,
  `State ConfigMethod=nil`). The Setup-first / State-fallback order in `ipv4ConfigMethod` is
  correct on this machine.
- Real snapshot values on the dev Mac:
  - `proxies=ProxySnapshot(http: nil, https: nil, socks: nil)` (no proxies active — struct still
    returns, all rows omitted; proxy formatting therefore not exercised against a live proxy).
  - `ipv6Router=fe80::e2d3:62ff:fe78:5ba4` (a link-local IPv6 router — surfaced verbatim as
    designed).
  - `ipv4ConfigMethod=DHCP`
  - `dhcpServer=10.0.0.1` (DHCP option 54 decoded to a dotted quad — 4-byte parse works).
  - `dhcpLeaseStart=2026-06-29 16:48:06 +0000` (`DHCPInfoGetLeaseStartTime` bridges to `Date`).
  - `computerName=Eurydice`
- No deviation from the design; all new fields populated as specified.

### Task 4 — InterfaceReader

- `ifmediareq` is declared in `<net/if.h>` (not `<net/if_media.h>`) under `#pragma pack(4)`, so
  its C `sizeof` is 44. `SIOCGIFMEDIA` (`_IOWR('i', 56, ifmediareq)`) is a function-like macro and
  is **not** imported into Swift, so `siocgifmedia` is computed from `<sys/ioccom.h>` using
  `MemoryLayout<ifmediareq>.stride`; it evaluates to the canonical `0xc02c6938` (verified against
  an independent computation).
- Verified via a throwaway diagnostic (now removed): the ioctl **succeeds** (returns 0) and
  populates `ifm_active` even when the mapping yields nil — `en0` (down Ethernet) returned
  `ifm_active=34` = IFM_ETHER + a non-link subtype, `en1` (Wi-Fi) returned `ifm_active=128` =
  IFM_IEEE80211. Both correctly map to nil (not Ethernet-with-a-speed-subtype). No active wired
  link was present on the dev Mac, so a real "1000baseT full-duplex" string was not observed live —
  that path is covered by the pure-helper unit tests.
- Real counter/broadcast values observed: `en1` (active Wi-Fi) `broadcast=10.0.0.255`,
  `rxBytes≈3.15 GB`, `rxPackets≈20.8 M`, `txPackets≈8.0 M`, `inErrors/outErrors/drops=0`; `lo0`
  counters present, media nil. `ifi_iqdrops` used for `drops`.
- `ipv6String(from:)` was generalized/renamed to `numericHost(from:)` (used by both the IPv6 and
  the new broadcast paths) — a rename, not a behavior change.

### Task 5 — WifiReader

- `interfaceMode` mapped by rawValue (1→Station, 2→IBSS, 3→Host AP; 0/unknown→nil) via a new
  internal `modeText(_:)` (made internal, not private, so it has a pure unit test — matching how
  `InterfaceReader.mediaDescription(active:)` is tested). `transmitPower() <= 0 → nil`.
- `powerOn()`/`serviceActive()` deliberately not surfaced, per design.

### Task 6 — PathReader (new file `QuickNetStats/Managers/PathReader.swift`)

- One-shot `NWPathMonitor` on a utility `DispatchQueue`, first callback awaited via a
  `CheckedContinuation`, raced against a `Task.sleep(timeout)` inside a `withTaskGroup`.
- **Bug caught during implementation**: the first draft's `onCancel` could not reach the
  continuation, so when the timeout won the race the cancelled child task would hang and, because
  `withTaskGroup` waits for all children, the whole call would hang. Fixed by moving the
  continuation into a lock-guarded `ResumeGuard` that both the monitor callback and `onCancel`
  resume through (single-resume guaranteed; a resume arriving before `attach` is stashed and
  delivered on attach — covers cancel-before-continuation-runs). The real-monitor smoke test
  returns in well under the timeout.
- `otherInterfaces` excludes the primary BSD name and loopback; formatted "TypeLabel (bsdName)".

### Task 7 — Manager assembly + live tick

- `pathReader: PathReading = PathReader()` added as the 4th reader seam; `fetchDetails` `async let`s
  the path snapshot alongside the public-IPv6 fetch.
- `supportsText(_:)` builds "IPv4 · IPv6 · DNS" (true flags only; all-false → "None"; all-nil → nil).
- `ByteSample` became `CounterSample` (bytes, packets, combined in+out errors, drops, timestamp).
  **Design-consistent choice**: `counterSample(from:)` is all-or-nothing — it returns nil unless
  every counter is present, since they all come from one `if_data64` read. Test fixtures/mocks were
  extended accordingly (`fullInterface` gains packet/error/drop base values; `MockInterfaceReader`
  grows packets alongside bytes). All rates reuse `bytesPerSecond` (reset/zero-elapsed guarded).

### Task 8 — Views

- **Deviation (improvement) from the plan wording**: the plan said add the Proxy group "with
  matching Divider handling". Blindly mirroring the existing unconditional `Divider()` pattern would
  show a stray divider for the majority (no-proxy) case, so the Proxy `Divider()` + group are gated
  together on `!details.proxyRows.isEmpty`. Matches the design intent ("group renders only when at
  least one is active").
- Four interface-agnostic Live rows ("Packets ↓/↑", "Errors", "Drops") added after Upload, before
  the RF rows; same idle-grayed "—" convention. Previews inherit the richer mocks automatically
  (the Wi-Fi preview now shows the Proxy group from `mockWifi`).

### Task 9 — Verification

- `swiftlint lint`: **0 violations, 0 serious** in 36 files (PathReader.swift confirmed linted
  separately: 0 violations).
- Full suite: **`** TEST SUCCEEDED **`, 0 failures**. xcodebuild's console per-function count was
  165 (the plan's "188" counts each parameterized argument separately — a different metric, per the
  known log-counting caveat). Net new test functions across Tasks 1–7: 28.
- Design cross-check: every field/row in the Overview and Design sections is implemented (Interface
  Media/Supports/Also available; Addressing Router (IPv6)/Broadcast/IPv4 config/Computer name;
  DNS & DHCP DHCP server/Lease started; Proxy HTTP/HTTPS/SOCKS; Wi-Fi Mode/Tx power; Live
  Packets ↓/↑, Errors, Drops). Nothing from the out-of-scope list was added.
- Not verified: a live wired Ethernet media string (no active wired link on the dev Mac — ioctl
  path proven to succeed and map to nil; the "1000baseT full-duplex" mapping is covered only by the
  pure-helper unit tests). Live proxy formatting against a real active proxy (none configured on the
  dev Mac). SwiftUI previews were not visually rendered (build + full suite green only, per plan).
