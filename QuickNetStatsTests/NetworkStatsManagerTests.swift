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

/// Container suite for tests that drive the shared `NotificationsManager.shared`
/// singleton. Swift Testing runs distinct top-level suites concurrently, but a
/// `.serialized` suite forces its nested suites to run one at a time (recursively).
/// `NetworkStatsManagerTests` (via `applyPollResult` → `publishStats` →
/// `checkForNotifications`) and `NotificationsManagerSettleTests` both mutate
/// `NotificationsManager.shared` state (`defaults`, `suppressSystemNotifications`,
/// `lastDeliveredNotification`); running them concurrently let one suite's async
/// settle window observe or clobber the other's singleton state, occasionally
/// firing a real system notification. Nesting both here under one `.serialized`
/// container eliminates that interleaving without touching production code.
@Suite(.serialized)
enum SingletonBoundSuites {}

extension SingletonBoundSuites {
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
            manager.lastPathStats = NetworkStats.mockGoodWifiConnection

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
            manager.lastPathStats = NetworkStats.mockGoodWifiConnection

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
}
