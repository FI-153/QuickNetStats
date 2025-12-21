//
//  NotificationsManager.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-21.
//

import UserNotifications
import Combine

class NotificationsManager: ObservableObject {
    
    private init(){}
    
    @Published var areNotificationsEnabled:Bool = false
    @Published var notificationAuthError:String?
    
    /// The shared instance of the NotificationsManager class
    static let shared = NotificationsManager()
    
    /// Request permisison to send a notification
    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Authorization Error: \(error.localizedDescription)")
                self.notificationAuthError = error.localizedDescription
            }
            
            self.areNotificationsEnabled = granted
        }
    }
    
    /// Schedule a notification to be sent immediatelly
    func scheduleNotification(with title:String, _ body :String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Trigger: now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0, repeats: false)

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
