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
        self.cooldown = 0.5
        self.previousNotifificationTime = Date.distantPast
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
    
    /// Send a notification with a notificaiton limit of one every `cooldown` seconds
    func notify(titled title:String, _ body :String) {
        if Date() < Date().addingTimeInterval(cooldown) { return }
        scheduleNotification(titled: title, body)
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
    
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Force the alert and sound even when the app is focused
        completionHandler([.banner, .sound])
    }
}
