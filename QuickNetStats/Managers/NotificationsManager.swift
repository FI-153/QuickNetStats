//
//  NotificationsManager.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-21.
//

import UserNotifications
import Combine

class NotificationsManager: ObservableObject {
    
    private init(){
        self.areNotificationsEnabled = false
        self.cooldown = 0.2
        self.previousNotifificationTime = Date.distantPast
        self.notificationStack = []
        checkNotificationStatus()
    }
    
    /// The shared instance of the NotificationsManager class
    static let shared = NotificationsManager()
    
    /// It is set to true when the user authorizes notifications and they are allowed in the settings page. If they are disabled by the user in settings
    /// then this value becomes false (eg. user authorized the app to send notifications but later disabled them in settings --> false)
    @Published var areNotificationsEnabled:Bool
    
    @Published var notificationAuthError:String?
    
    /// The cooldown time in seconds between two notificaitons
    private var cooldown:Double
    
    /// The last time a notification was sent
    private var previousNotifificationTime:Date
    
    /// A stack that collects all notifications requests
    private var notificationStack:[Notification]
        
    /// Checks the current notification permission status from system settings
    func checkNotificationStatus() -> Void {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.areNotificationsEnabled = (settings.authorizationStatus == .authorized)
            }
        }
    }
    
    /// Request permisison to send a notification
    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Authorization Error: \(error.localizedDescription)")
                    self.notificationAuthError = error.localizedDescription
                }
                
                self.areNotificationsEnabled = granted
            }
        }
    }
    
    /// Send a notification
    func notify(titled title:String, _ body :String) {
        scheduleNotification(titled: title, body)
    }
    
    /// Send a notification
    func notify(_ notification:Notification) {
        scheduleNotification(titled: notification.title, notification.body)
    }
    
    /// Schedule a notification to be sent immediatelly
    private func scheduleNotification(titled title:String, _ body :String) {
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
        UserDefaults.standard.bool(forKey: Settings.UserDefaultsKeys.isNotificationActive)
    }
        
    /// Queue notifications to be sent once every `cooldown` period
    func checkForNotifications(oldStats: NetworkStats, newStats: NetworkStats) {
        
        guard self.notificationsGloballyEnabled() else { return }
        
        // Internet onnection
        if let new_notification = self.checkInternetStatusChanges(
            wasConnected: oldStats.isConnected,
            isConnected: newStats.isConnected,
            newInterface: newStats.interfaceType,
        ) {
            notificationStack.append(new_notification)
        }
        
        // Interface
        if let new_notification = self.checkInterfaceChanges(
            wasConnected: oldStats.isConnected,
            isConnected: newStats.isConnected,
            oldInterface: oldStats.interfaceType,
            newInterface: newStats.interfaceType
        ) {
            notificationStack.append(new_notification)
        }
        
        // Link quality
        if let new_notification = self.checkLinkQualityChanges(
            oldQuality: oldStats.linkQuality?.rawValue ?? 0,
            newQuality: newStats.linkQuality?.rawValue ?? 0
        ) {
            notificationStack.append(new_notification)
        }
                
        sendMostImportantNotificationOnStack()
    }
    
    /// Send the most important notification on the `notificationStack` if the `cooldown` period has passed.
    /// If a notificaiton is sent, it then empties `notificationStack` and sets a new `previousNotifificationTime`
    private func sendMostImportantNotificationOnStack() {
        if Date() >= self.previousNotifificationTime
            .addingTimeInterval(self.cooldown) {
            if !notificationStack.isEmpty {
                notificationStack.sort()
                self.notify(notificationStack.removeFirst())
                self.notificationStack = []
                self.previousNotifificationTime = Date()
            }
        }
    }
    
    /// Check internet status changes based on what the user configured on the settings.
    /// If the status has changes and the notification cooldown is over then send the notification
    private func checkInternetStatusChanges(
        wasConnected:Bool,
        isConnected:Bool,
        newInterface:NetworkInterfaceType,
        defaults:UserDefaults = UserDefaults.standard
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
    
    /// Check the link quality changes based on what the user configured on the settings
    /// If the status has changes and the notification cooldown is over then send the notification
    private func checkLinkQualityChanges(
        oldQuality:Int,
        newQuality:Int,
        defaults:UserDefaults = UserDefaults.standard
    ) -> LinkQualityStatusNotification? {
        let liknQualityNotificationsBehavior = LinkQualityNotificationBehavior(
            rawValue: defaults
                .integer(
                    forKey: Settings.UserDefaultsKeys.notifyQualityBehavior
                )
        ) ?? .changes
                
        if oldQuality != newQuality {
            var shouldNotify = false
            var title = ""
            
            switch liknQualityNotificationsBehavior {
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
    
    /// Check if the interface changed and notiffies if the user toggled this notification
    /// If the status has changes and the notification cooldown is over then send the notification
    private func checkInterfaceChanges(
        wasConnected:Bool,
        isConnected:Bool,
        oldInterface:NetworkInterfaceType,
        newInterface:NetworkInterfaceType,
        defaults:UserDefaults = UserDefaults.standard
    ) -> LinkQualityStatusNotification? {
        if defaults.bool(forKey: Settings.UserDefaultsKeys.notifyInterfaceChanges) {
            if wasConnected && isConnected && oldInterface != newInterface {
                return LinkQualityStatusNotification(
                    title: "Network Changed",
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
