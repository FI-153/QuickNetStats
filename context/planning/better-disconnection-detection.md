# Plan: Better Disconnection Detection via Public IP Reachability

> **Date**: 2026-04-11
> **Scope**: Enhance `NetworkStatsManager` to verify internet reachability via public endpoint checks, complementing the existing `NWPathMonitor`-based detection
> **Prerequisite**: None

---

## Context

Currently, QuickNetStats relies solely on `NWPathMonitor` to determine internet connectivity. `NWPathMonitor` reports path status (`.satisfied` / `.unsatisfied`) based on the local network stack — but this can produce false positives. A path can be `.satisfied` (e.g., connected to a router) while the internet is actually unreachable (captive portal, upstream outage, misconfigured router, certain VPN scenarios).

The app needs a secondary signal — attempting to reach a public endpoint — to confirm actual internet connectivity. When the public check fails, the app should behave identically to a full disconnection: same UI, same notifications, same menu bar state.

---

## Overview

```
NWPathMonitor
    │
    ▼
pathUpdateHandler fires
    │
    ├─ path.status == .unsatisfied ──► publish defaultOffline (no IP check)
    │                                   stop timer
    │
    └─ path.status == .satisfied ───► run reachability check (sequential fallback)
                                        │
                                        ├─ pass ──► publish real NetworkStats
                                        │           start/reset 15s timer
                                        │
                                        └─ fail ──► publish defaultOffline
                                                    stop timer

Timer (every 15s, while connected)
    │
    ▼
run reachability check ──► pass: no-op (stay connected)
                         └─ fail: publish defaultOffline, stop timer
```

---

## Design

### Reachability Check

A new private async method in `NetworkStatsManager`:

```
func checkInternetReachability() async -> Bool
```

- Tries three endpoints **sequentially**, stopping at the first success:
  1. `https://captive.apple.com`
  2. `http://connectivitycheck.gstatic.com/generate_204`
  3. `https://1.1.1.1/cdn-cgi/trace`
- Each request uses a dedicated `URLSessionConfiguration` with a **5-second timeout** (`timeoutIntervalForRequest` and `timeoutIntervalForResource`)
- Returns `true` on any 2xx response from any endpoint; `false` if all three fail
- Does **not** store the response body — this is a pass/fail check only

### Modified Path Update Flow

The `pathUpdateHandler` changes from synchronous to async-aware:

1. NWPath fires with a new path
2. If `path.status != .satisfied` → publish `defaultOffline`, stop timer, cancel any in-flight check
3. If `path.status == .satisfied` → cancel any in-flight check, start a new reachability check:
   - **Pass**: publish `NetworkStats(path: path)`, start/reset 15s timer
   - **Fail**: publish `defaultOffline`, stop timer

The in-flight check is tracked via a stored `Task` reference. When a new path update arrives or `stopMonitoring()` is called, the task is cancelled.

### Periodic Timer

- Implemented as a `Timer.publish(every: 15, on: .main, in: .common)` or `DispatchSourceTimer`
- **Starts** when a path update results in a passed reachability check
- **Stops** when:
  - Reachability check fails (from timer tick or path update)
  - NWPath reports `.unsatisfied`
  - `stopMonitoring()` is called
- **On tick**: runs the reachability check
  - Pass → no action, wait for next tick
  - Fail → publish `defaultOffline`, fire notifications, stop timer
- **On path update while timer is running**: timer resets to avoid double-checking close together

### Notification Integration

**No changes to `NotificationsManager`.** The existing `checkForNotifications(oldStats:newStats:)` call remains in `NetworkStatsManager`. Because `defaultOffline` has `isConnected == false`, the notification system sees a disconnection and fires the appropriate notification. Reconnection is detected when the next path update passes the reachability check.

### NetworkDetailsManager Integration

**No changes to `NetworkDetailsManager`.** It continues to fetch the public IP from `api.ipify.org` independently for display purposes. The two managers share no state — they happen to make HTTP requests but for different purposes (reachability vs. display).

### Properties Added to NetworkStatsManager

| Property | Type | Purpose |
|----------|------|---------|
| `reachabilityTask` | `Task<Void, Never>?` | Tracks in-flight reachability check for cancellation |
| `pollingTimer` | Timer/DispatchSourceTimer | 15-second periodic reachability check |
| `reachabilitySession` | `URLSession` | Dedicated session with 5s timeout configuration |

---

## Edge Cases & Constraints

1. **Race condition: NWPath fires while IP check is in-flight** — The stored `reachabilityTask` is cancelled before starting a new check. The cancelled task's result is ignored.

2. **App launch** — The `isFirstUpdate` flag suppresses notifications on the first path update. The reachability check still runs to establish the real initial state.

3. **Rapid path flapping** — Each path update cancels the previous in-flight check and starts a fresh one. `NotificationsManager`'s 1.0s settle delay absorbs notification noise.

4. **All endpoints down but internet works** — False positive: app shows disconnected. Extremely unlikely given three independent endpoints (Apple, Google, Cloudflare). Accepted trade-off.

5. **5-second timeout** — Prevents the check from hanging on slow/broken connections. Short enough to feel responsive, long enough to tolerate normal latency. Worst case (all three fail sequentially): 15 seconds total.

6. **Timer not running when disconnected** — No wasted requests when NWPath already reports `.unsatisfied`. Reconnection is detected when NWPath fires `.satisfied` again, which triggers a reachability check.

---

## Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate `NetworkStatsManager`'s published `netStats` on a public endpoint reachability check so the app detects internet loss even when `NWPathMonitor` reports `.satisfied`.

**Architecture:** A new `InternetReachabilityChecker` (protocol + concrete class) handles the sequential-fallback HTTP check. `NetworkStatsManager` gains an injected checker, a gated path-update flow, and a 15-second polling loop. No downstream changes to UI or notifications.

**Tech Stack:** Swift Testing, URLSession, URLProtocol (for test mocking), Network framework (existing)

---

### File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `QuickNetStats/Managers/InternetReachabilityChecker.swift` | Protocol + concrete reachability checker |
| Create | `QuickNetStatsTests/InternetReachabilityCheckerTests.swift` | Tests for the checker (MockURLProtocol + 5 test cases) |
| Modify | `QuickNetStats/Managers/NetworkStatsManager.swift` | Inject checker, gate path updates, add polling |

> **Note:** New files must be added to the appropriate Xcode target (app target for production code, test target for test code).

---

### Task 1: Write failing tests for `InternetReachabilityChecker`

**Files:**
- Create: `QuickNetStatsTests/InternetReachabilityCheckerTests.swift`

- [x] **Step 1.1: Create the test file with `MockURLProtocol` and all test cases**

Create `QuickNetStatsTests/InternetReachabilityCheckerTests.swift`:

```swift
//
//  InternetReachabilityCheckerTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

// MARK: - Mock URL Protocol

/// A mock URL protocol that intercepts all requests and returns configurable responses.
/// Uses a static `requestHandler` closure to determine behavior per request.
class MockURLProtocol: URLProtocol {

    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Tests

@Suite("InternetReachabilityChecker", .serialized)
struct InternetReachabilityCheckerTests {

    /// Creates a `URLSession` that routes all requests through `MockURLProtocol`.
    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("Returns true when first endpoint succeeds")
    func firstEndpointSucceeds() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let checker = InternetReachabilityChecker(session: mockSession())
        let result = await checker.checkReachability()
        #expect(result == true)
    }

    @Test("Returns false when all endpoints fail with network error")
    func allEndpointsFailWithError() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let checker = InternetReachabilityChecker(session: mockSession())
        let result = await checker.checkReachability()
        #expect(result == false)
    }

    @Test("Returns false when all endpoints return non-2xx status")
    func allEndpointsReturnServerError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 503,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let checker = InternetReachabilityChecker(session: mockSession())
        let result = await checker.checkReachability()
        #expect(result == false)
    }

    @Test("Falls back to second endpoint when first fails")
    func fallsBackToSecondEndpoint() async {
        MockURLProtocol.requestHandler = { request in
            if request.url!.absoluteString.contains("captive.apple.com") {
                throw URLError(.timedOut)
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let checker = InternetReachabilityChecker(session: mockSession())
        let result = await checker.checkReachability()
        #expect(result == true)
    }

    @Test("Falls back to third endpoint when first two fail")
    func fallsBackToThirdEndpoint() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            if url.contains("captive.apple.com") || url.contains("connectivitycheck") {
                throw URLError(.timedOut)
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let checker = InternetReachabilityChecker(session: mockSession())
        let result = await checker.checkReachability()
        #expect(result == true)
    }
}
```

- [x] **Step 1.2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'
```
Expected: **Build failure** — `InternetReachabilityChecker` type does not exist.

---

### Task 2: Implement `InternetReachabilityChecker` to make tests pass

**Files:**
- Create: `QuickNetStats/Managers/InternetReachabilityChecker.swift`

- [x] **Step 2.1: Create the protocol and implementation**

Create `QuickNetStats/Managers/InternetReachabilityChecker.swift`:

```swift
//
//  InternetReachabilityChecker.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-04-11.
//

import Foundation

// MARK: - Protocol

/// Checks whether the device can reach the public internet.
protocol InternetReachabilityChecking {
    /// Returns `true` if at least one public endpoint is reachable.
    func checkReachability() async -> Bool
}

// MARK: - Implementation

/// Tries a sequence of well-known public endpoints to confirm internet reachability.
/// Stops at the first success; returns `false` only if all endpoints fail.
class InternetReachabilityChecker: InternetReachabilityChecking {

    /// The endpoints to try, in order.
    private let endpoints: [URL] = [
        URL(string: "https://captive.apple.com")!,
        URL(string: "https://connectivitycheck.gstatic.com/generate_204")!,
        URL(string: "https://1.1.1.1/cdn-cgi/trace")!
    ]

    /// A dedicated session with short timeouts for reachability checks.
    private let session: URLSession

    /// Creates a checker with the given session (injectable for testing).
    init(session: URLSession = .reachabilitySession) {
        self.session = session
    }

    func checkReachability() async -> Bool {
        for endpoint in endpoints {
            do {
                let (_, response) = try await session.data(from: endpoint)
                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }
}

// MARK: - URLSession Extension

extension URLSession {

    /// A session configured with 5-second timeouts for reachability checks.
    static var reachabilitySession: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }
}
```

- [x] **Step 2.2: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'
```
Expected: **All 5 `InternetReachabilityCheckerTests` pass.** All pre-existing tests still pass.

- [x] **Step 2.3: Lint**

Run:
```bash
swiftlint lint
```
Fix any violations in the new files.

---

### Task 3: Modify `NetworkStatsManager` to use reachability checker

**Files:**
- Modify: `QuickNetStats/Managers/NetworkStatsManager.swift`

- [x] **Step 3.1: Add new properties and modify `init`**

Add these properties to `NetworkStatsManager`:

```swift
/// The reachability checker used to verify internet connectivity.
private let reachabilityChecker: InternetReachabilityChecking

/// Tracks the in-flight reachability check so it can be cancelled on new path updates.
private var reachabilityTask: Task<Void, Never>?

/// Tracks the polling loop task so it can be cancelled on disconnect or stop.
private var pollingTask: Task<Void, Never>?
```

Update `init` to accept an injectable checker:

```swift
init(reachabilityChecker: InternetReachabilityChecking = InternetReachabilityChecker()) {
    self.monitor = NWPathMonitor()
    self.queue = DispatchQueue(label: "com.quickconncheck.networkMonitor")
    self.netStats = NetworkStats.defaultOffline
    self.isMonitoring = false
    self.isFirstUpdate = true
    self.reachabilityChecker = reachabilityChecker
    startMonitoring()
}
```

- [x] **Step 3.2: Extract `publishStats` helper method**

Add a method that centralises notification dispatch and state update:

```swift
/// Publishes new stats, sending notifications unless this is the first update.
private func publishStats(_ newStats: NetworkStats) {
    if isFirstUpdate {
        isFirstUpdate = false
        netStats = newStats
        return
    }

    NotificationsManager.shared.checkForNotifications(
        oldStats: netStats,
        newStats: newStats
    )
    netStats = newStats
}
```

- [x] **Step 3.3: Replace `pathUpdateHandler` with reachability-gated flow**

Replace the body of `startMonitoring()` (the `pathUpdateHandler` closure) with:

```swift
func startMonitoring() {
    guard !isMonitoring else { return }

    monitor.pathUpdateHandler = { [weak self] path in
        DispatchQueue.main.async {
            guard let self = self else { return }
            self.handlePathUpdate(path)
        }
    }

    monitor.start(queue: queue)
    self.isMonitoring = true
}
```

Add the new `handlePathUpdate` method:

```swift
/// Processes a path update from NWPathMonitor, gating on reachability when connected.
private func handlePathUpdate(_ path: NWPath) {
    let pathStats = NetworkStats(path: path)

    // Cancel any in-flight reachability check
    reachabilityTask?.cancel()

    guard pathStats.isConnected else {
        // Path says disconnected — publish immediately, stop polling
        stopPolling()
        publishStats(pathStats)
        return
    }

    // Path says connected — verify with reachability check
    reachabilityTask = Task {
        let reachable = await reachabilityChecker.checkReachability()
        guard !Task.isCancelled else { return }

        if reachable {
            self.publishStats(pathStats)
            self.startPolling()
        } else {
            self.publishStats(NetworkStats.defaultOffline)
            self.stopPolling()
        }
    }
}
```

- [x] **Step 3.4: Add polling methods**

Add the polling loop and its control methods:

```swift
/// Starts the 15-second periodic reachability polling loop.
private func startPolling() {
    stopPolling()
    pollingTask = Task {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { break }
            await pollReachability()
        }
    }
}

/// Stops the periodic polling loop.
private func stopPolling() {
    pollingTask?.cancel()
    pollingTask = nil
}

/// Runs a single reachability check from the polling loop.
private func pollReachability() async {
    let reachable = await reachabilityChecker.checkReachability()
    guard !Task.isCancelled else { return }

    if !reachable {
        publishStats(NetworkStats.defaultOffline)
        stopPolling()
    }
}
```

- [x] **Step 3.5: Update `stopMonitoring` and `deinit` for cleanup**

Update `stopMonitoring()` to cancel in-flight tasks and the polling loop:

```swift
private func stopMonitoring() {
    guard self.isMonitoring else { return }

    self.isMonitoring = false
    reachabilityTask?.cancel()
    stopPolling()
    self.netStats = NetworkStats.defaultOffline
    monitor.cancel()
    monitor = NWPathMonitor()
}
```

`deinit` already calls `stopMonitoring()`, so no change needed there.

- [x] **Step 3.6: Build and run tests**

Run:
```bash
xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'
```
Expected: **Build succeeds. All tests pass** (both new and pre-existing).

- [x] **Step 3.7: Lint**

Run:
```bash
swiftlint lint
```
Fix any violations.

---

### Task 4: Final verification

- [x] **Step 4.1: Run the full test suite**

Run:
```bash
xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'
```
Expected: **All tests pass**, no warnings or errors.

- [x] **Step 4.2: Run SwiftLint**

Run:
```bash
swiftlint lint
```
Expected: **No violations** in new or modified files.

- [x] **Step 4.3: Build release configuration**

Run:
```bash
xcodebuild -project QuickNetStats.xcodeproj -scheme QuickNetStats -configuration Release build
```
Expected: **Build succeeds** with no errors.
