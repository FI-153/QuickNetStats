//
//  NotificationsManager.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-21.
//

import UserNotifications
import Combine

class NotificationsManager: ObservableObject {
    
    private init() {
        self.areNotificationsEnabled = false
        checkNotificationStatus()
    }

    /// The shared instance of the NotificationsManager class
    static let shared = NotificationsManager()

    /// It is set to true when the user authorizes notifications and they are allowed in the settings page. If they are disabled by the user in settings
    /// then this value becomes false (eg. user authorized the app to send notifications but later disabled them in settings --> false)
    @Published var areNotificationsEnabled: Bool

    @Published var notificationAuthError: String?

    /// Duration in seconds to wait for the network state to settle before evaluating notifications
    private let settleDelay: TimeInterval = 1.0

    /// Snapshot of the network state when the first change in a settle window arrived
    private var originalStats: NetworkStats?

    /// Most recent network state received during the current settle window
    private var latestStats: NetworkStats?

    /// The pending settle task; cancelled and restarted on each new event
    private var settleTask: Task<Void, Never>?

    /// User defaults used to read notification preferences; overridable in tests to
    /// avoid polluting the real preferences.
    var defaults: UserDefaults = .standard

    /// The most recent notification delivered through the settle pipeline. Exposed for testing.
    var lastDeliveredNotification: AppNotification?

    /// When true, `scheduleNotification` short-circuits so tests never hit the system center.
    var suppressSystemNotifications = false
        
    /// Checks the current notification permission status from system settings
    func checkNotificationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            self.areNotificationsEnabled = (settings.authorizationStatus == .authorized)
        }
    }

    /// Request permission to send a notification
    func requestNotificationPermission() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                self.areNotificationsEnabled = granted
            } catch {
                print("Authorization Error: \(error.localizedDescription)")
                self.notificationAuthError = error.localizedDescription
            }
        }
    }
    
    /// Send a notification
    func notify(titled title: String, _ body: String) {
        scheduleNotification(titled: title, body)
    }
    
    /// Send a notification
    func notify(_ notification: AppNotification) {
        lastDeliveredNotification = notification
        scheduleNotification(titled: notification.title, notification.body)
    }

    /// Schedule a notification to be sent immediately
    private func scheduleNotification(titled title: String, _ body: String) {
        guard !suppressSystemNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Trigger: now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        )
    }
    
    private func notificationsGloballyEnabled() -> Bool {
        defaults.bool(forKey: Settings.UserDefaultsKeys.isNotificationActive)
    }
        
    /// Queue a settle evaluation. On first change, snapshots the original state.
    /// Each subsequent change restarts the timer. When the timer fires after
    /// `settleDelay` seconds of quiet, compares original vs settled state.
    func checkForNotifications(oldStats: NetworkStats, newStats: NetworkStats) {
        guard self.notificationsGloballyEnabled() else { return }

        // Snapshot original state on the first change in this settle window
        if originalStats == nil {
            originalStats = oldStats
        }
        latestStats = newStats

        // Cancel any pending task and start a new one
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.settleDelay ?? 1.0))
            guard !Task.isCancelled else { return }
            self?.evaluateSettledState()
        }
    }

    /// Called when the settle timer fires. Compares original vs settled state
    /// and sends at most one notification (the highest priority).
    private func evaluateSettledState() {
        guard let original = originalStats, let settled = latestStats else {
            originalStats = nil
            latestStats = nil
            settleTask = nil
            return
        }

        // Reset settle window
        originalStats = nil
        latestStats = nil
        settleTask = nil

        let defaults = self.defaults

        // Evaluate all three categories
        var candidates: [AppNotification] = []

        if let internetNotification = checkInternetStatusChanges(
            wasConnected: original.isConnected,
            isConnected: settled.isConnected,
            newInterface: settled.interfaceType,
            defaults: defaults
        ) {
            candidates.append(internetNotification)
        }

        if let interfaceNotification = checkInterfaceChanges(
            wasConnected: original.isConnected,
            isConnected: settled.isConnected,
            oldInterface: original.interfaceType,
            newInterface: settled.interfaceType,
            defaults: defaults
        ) {
            candidates.append(interfaceNotification)
        }

        if let qualityNotification = checkLinkQualityChanges(
            oldQuality: original.linkQuality?.rawValue ?? 0,
            newQuality: settled.linkQuality?.rawValue ?? 0,
            defaults: defaults
        ) {
            candidates.append(qualityNotification)
        }

        // Send only the highest-priority notification (Notification conforms to Comparable)
        if let best = candidates.min() {
            notify(best)
        }
    }
    
    /// Check internet status changes based on what the user configured in settings
    func checkInternetStatusChanges(
        wasConnected: Bool,
        isConnected: Bool,
        newInterface: NetworkInterfaceType,
        defaults: UserDefaults = UserDefaults.standard
    ) -> InternetStatusNotification? {
        let internetNotificationsBehavior = InternetNotificationBehavior(
            rawValue: defaults.integer(forKey: Settings.UserDefaultsKeys.notifyInternetBehavior)
        ) ?? .connects
                
        if wasConnected != isConnected {
            var shouldNotify = false
            var title = ""
            var body = ""
            
            switch internetNotificationsBehavior {
            case .connects:
                if isConnected {
                    shouldNotify = true
                    title = "Internet Connected"
                    body = "You are now connected to \(newInterface.rawValue)"
                }
            case .disconnects:
                if !isConnected {
                    shouldNotify = true
                    title = "Internet Disconnected"
                    body = "You are now disconnected from the internet"
                }
            case .changes:
                shouldNotify = true
                if isConnected {
                    title = "Internet Connected"
                    body = "You are now connected to \(newInterface.rawValue)"
                } else {
                    title = "Internet Disconnected"
                    body = "You are now disconnected from the internet"
                }
            }
            
            if shouldNotify {
                return InternetStatusNotification(
                    title: title,
                    body: body,
                    created: Date()
                )
            }
        }
        
        return nil
    }
    
    /// Check link quality changes based on what the user configured in settings
    func checkLinkQualityChanges(
        oldQuality: Int,
        newQuality: Int,
        defaults: UserDefaults = UserDefaults.standard
    ) -> LinkQualityStatusNotification? {
        let linkQualityNotificationsBehavior = LinkQualityNotificationBehavior(
            rawValue: defaults
                .integer(
                    forKey: Settings.UserDefaultsKeys.notifyQualityBehavior
                )
        ) ?? .changes
                
        if oldQuality != newQuality {
            var shouldNotify = false
            var title = ""
            
            switch linkQualityNotificationsBehavior {
            case .improves:
                if newQuality > oldQuality {
                    shouldNotify = true
                    title = "Network Quality Improved"
                }
            case .worsens:
                if newQuality < oldQuality {
                    shouldNotify = true
                    title = "Network Quality Worsened"
                }
            case .changes:
                shouldNotify = true
                title = "Network Quality \(newQuality > oldQuality ? "Improved" : "Worsened")"
            }
            
            if shouldNotify {
                return LinkQualityStatusNotification(
                    title: title,
                    body: "",
                    created: Date()
                )
            }
        }
        
        return nil
    }
    
    /// Check if the interface changed and notify if the user enabled this notification
    func checkInterfaceChanges(
        wasConnected: Bool,
        isConnected: Bool,
        oldInterface: NetworkInterfaceType,
        newInterface: NetworkInterfaceType,
        defaults: UserDefaults = UserDefaults.standard
    ) -> InterfaceChangesStatusNotification? {
        if defaults.bool(forKey: Settings.UserDefaultsKeys.notifyInterfaceChanges) {
            if wasConnected && isConnected && oldInterface != newInterface {
                return InterfaceChangesStatusNotification(
                    title: "Network Interface Changed",
                    body: "Switched to \(newInterface.rawValue.capitalized)",
                    created: Date()
                )
            }
        }
        
        return nil
    }
    
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Force the alert and sound even when the app is focused
        completionHandler([.banner, .sound])
    }
}
