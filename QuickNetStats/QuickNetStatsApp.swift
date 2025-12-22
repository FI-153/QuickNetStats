//
//  QuickNetStatsApp.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-07.
//

import SwiftUI
import UserNotifications

@main
struct QuickNetStatsApp: App {
    
    @StateObject var netStatsManager:NetworkStatsManager = NetworkStatsManager()
    @StateObject var netDetailsManager:NetworkDetailsManager = NetworkDetailsManager()
    @StateObject var settings:Settings = Settings()
    
    let notificationDelegate = NotificationDelegate()
    
    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }
    
    var body: some Scene {
        MenuBarExtra( content: {
            ContentView(
                netStatsManager: netStatsManager,
                netDetailsManager: netDetailsManager
            )
            .padding()
            .frame(width: 550)
            .task {
                await netDetailsManager.getAddresses()
            }
            .environmentObject(settings)
            
        }, label: {
            if settings.showSummaryInMenu {
                Text(netStatsManager.netStats.summary)
            } else {
                Image(systemName: "network")
            }
        }
        )
        .menuBarExtraStyle(.window)
        
        // Scene 2: The Settings Window
        WindowGroup(id: "settings-window") {
            SettingsView() // Replace with your actual Settings View
                .environmentObject(settings)
                .frame(minWidth: 300, minHeight: 400) // Set reasonable defaults
        }
        .windowResizability(.contentSize) // Optional: locks size to content
        .defaultPosition(.center) // Optional: centers on screen
    }
    
}
