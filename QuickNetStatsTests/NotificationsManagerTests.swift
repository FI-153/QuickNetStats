//
//  NotificationsManagerTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

@Suite("NotificationsManager Check Methods")
struct NotificationsManagerCheckTests {

    let manager = NotificationsManager.shared

    /// Creates a fresh UserDefaults suite for each test to avoid cross-contamination
    func testDefaults(
        internetBehavior: InternetNotificationBehavior = .connects,
        qualityBehavior: LinkQualityNotificationBehavior = .changes,
        interfaceChanges: Bool = false
    ) -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(internetBehavior.rawValue, forKey: Settings.UserDefaultsKeys.notifyInternetBehavior)
        defaults.set(qualityBehavior.rawValue, forKey: Settings.UserDefaultsKeys.notifyQualityBehavior)
        defaults.set(interfaceChanges, forKey: Settings.UserDefaultsKeys.notifyInterfaceChanges)
        return defaults
    }

    // MARK: - Internet status changes

    @Test("Notifies on connect when behavior is .connects")
    func notifyOnConnect() {
        let defaults = testDefaults(internetBehavior: .connects)
        let result = manager.checkInternetStatusChanges(
            wasConnected: false, isConnected: true,
            newInterface: .wifi, defaults: defaults
        )
        #expect(result != nil)
        #expect(result?.title == "Internet Connected")
    }

    @Test("Does not notify on disconnect when behavior is .connects")
    func silentOnDisconnectWhenConnects() {
        let defaults = testDefaults(internetBehavior: .connects)
        let result = manager.checkInternetStatusChanges(
            wasConnected: true, isConnected: false,
            newInterface: .none, defaults: defaults
        )
        #expect(result == nil)
    }

    @Test("Notifies on disconnect when behavior is .disconnects")
    func notifyOnDisconnect() {
        let defaults = testDefaults(internetBehavior: .disconnects)
        let result = manager.checkInternetStatusChanges(
            wasConnected: true, isConnected: false,
            newInterface: .none, defaults: defaults
        )
        #expect(result != nil)
        #expect(result?.title == "Internet Disconnected")
    }

    @Test("Notifies on both connect and disconnect when behavior is .changes")
    func notifyOnBothChanges() {
        let defaults = testDefaults(internetBehavior: .changes)

        let connectResult = manager.checkInternetStatusChanges(
            wasConnected: false, isConnected: true,
            newInterface: .wifi, defaults: defaults
        )
        #expect(connectResult != nil)

        let disconnectResult = manager.checkInternetStatusChanges(
            wasConnected: true, isConnected: false,
            newInterface: .none, defaults: defaults
        )
        #expect(disconnectResult != nil)
    }

    @Test("Returns nil when connection status unchanged")
    func noNotificationWhenUnchanged() {
        let defaults = testDefaults(internetBehavior: .changes)
        let result = manager.checkInternetStatusChanges(
            wasConnected: true, isConnected: true,
            newInterface: .wifi, defaults: defaults
        )
        #expect(result == nil)
    }

    // MARK: - Link quality changes

    @Test("Notifies on quality improvement when behavior is .improves")
    func notifyOnImprovement() {
        let defaults = testDefaults(qualityBehavior: .improves)
        let result = manager.checkLinkQualityChanges(
            oldQuality: LinkQuality.minimal.rawValue,
            newQuality: LinkQuality.good.rawValue,
            defaults: defaults
        )
        #expect(result != nil)
        #expect(result?.title == "Network Quality Improved")
    }

    @Test("Does not notify on quality worsening when behavior is .improves")
    func silentOnWorseningWhenImproves() {
        let defaults = testDefaults(qualityBehavior: .improves)
        let result = manager.checkLinkQualityChanges(
            oldQuality: LinkQuality.good.rawValue,
            newQuality: LinkQuality.minimal.rawValue,
            defaults: defaults
        )
        #expect(result == nil)
    }

    @Test("Notifies on quality worsening when behavior is .worsens")
    func notifyOnWorsening() {
        let defaults = testDefaults(qualityBehavior: .worsens)
        let result = manager.checkLinkQualityChanges(
            oldQuality: LinkQuality.good.rawValue,
            newQuality: LinkQuality.minimal.rawValue,
            defaults: defaults
        )
        #expect(result != nil)
        #expect(result?.title == "Network Quality Worsened")
    }

    @Test("Returns nil when quality unchanged")
    func noNotificationWhenQualityUnchanged() {
        let defaults = testDefaults(qualityBehavior: .changes)
        let result = manager.checkLinkQualityChanges(
            oldQuality: LinkQuality.good.rawValue,
            newQuality: LinkQuality.good.rawValue,
            defaults: defaults
        )
        #expect(result == nil)
    }

    // MARK: - Interface changes

    @Test("Notifies on interface change when enabled and both connected")
    func notifyOnInterfaceChange() {
        let defaults = testDefaults(interfaceChanges: true)
        let result = manager.checkInterfaceChanges(
            wasConnected: true, isConnected: true,
            oldInterface: .wifi, newInterface: .ethernet,
            defaults: defaults
        )
        #expect(result != nil)
        #expect(result?.title == "Network Interface Changed")
    }

    @Test("Does not notify on interface change when disabled")
    func silentWhenInterfaceChangesDisabled() {
        let defaults = testDefaults(interfaceChanges: false)
        let result = manager.checkInterfaceChanges(
            wasConnected: true, isConnected: true,
            oldInterface: .wifi, newInterface: .ethernet,
            defaults: defaults
        )
        #expect(result == nil)
    }

    @Test("Does not notify on interface change when disconnecting")
    func silentWhenDisconnecting() {
        let defaults = testDefaults(interfaceChanges: true)
        let result = manager.checkInterfaceChanges(
            wasConnected: true, isConnected: false,
            oldInterface: .wifi, newInterface: .none,
            defaults: defaults
        )
        #expect(result == nil)
    }

    @Test("Does not notify when interface stays the same")
    func silentWhenInterfaceSame() {
        let defaults = testDefaults(interfaceChanges: true)
        let result = manager.checkInterfaceChanges(
            wasConnected: true, isConnected: true,
            oldInterface: .wifi, newInterface: .wifi,
            defaults: defaults
        )
        #expect(result == nil)
    }
}

// `NotificationsManagerSettleTests` is nested under `SingletonBoundSuites`
// (declared in NetworkStatsManagerTests.swift) because it drives the shared
// `NotificationsManager.shared` singleton, same as `NetworkStatsManagerTests`.
// See that container's doc comment for why the two must not run concurrently.
extension SingletonBoundSuites {
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

            let connected = NetworkStats.mockGoodWifiConnection
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
                oldStats: NetworkStats.mockGoodWifiConnection,
                newStats: NetworkStats.mockDisconnected
            )

            try? await Task.sleep(for: .seconds(2))

            #expect(manager.lastDeliveredNotification?.title == "Internet Disconnected")
        }
    }
}
