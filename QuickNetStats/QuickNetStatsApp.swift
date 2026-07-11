//
//  QuickNetStatsApp.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-07.
//

import SwiftUI
import Combine
import UserNotifications

@main
struct QuickNetStatsApp: App {
    
    @StateObject var netStatsManager: NetworkStatsManager = NetworkStatsManager()
    @StateObject var netDetailsManager: NetworkDetailsManager = NetworkDetailsManager()
    @StateObject var connectionDetailsManager: ConnectionDetailsManager = ConnectionDetailsManager()
    @StateObject var settings: Settings = Settings()
    
    let notificationDelegate = NotificationDelegate()
    
    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }
    
    var body: some Scene {
        MenuBarExtra(
            content: {
                ContentView(
                    netStatsManager: netStatsManager,
                    netDetailsManager: netDetailsManager,
                    connectionDetailsManager: connectionDetailsManager
                )
                .padding()
                .frame(width: 550)
                .task {
                    // Invalidate cached details/IPs whenever the connection changes.
                    // `.dropFirst()` skips the value $netStats replays to a new
                    // subscriber so app launch doesn't trigger a pointless flush.
                    // Both observe calls are idempotent, so re-running .task on each
                    // popover appearance re-subscribes only once.
                    // Note: the manual refresh button restarts NWPathMonitor and
                    // re-publishes, so it additionally triggers one flush+refetch here
                    // — harmless.
                    connectionDetailsManager.observeConnectionChanges(
                        netStatsManager.$netStats.dropFirst().eraseToAnyPublisher()
                    )
                    netDetailsManager.observeConnectionChanges(
                        netStatsManager.$netStats.dropFirst().eraseToAnyPublisher()
                    )
                    await netDetailsManager.getAddresses()
                }
                .environmentObject(settings)
                
            },
            label: {
                if settings.showSummaryInMenu {
                    Text(
                        settings.showQualityInMenu ? netStatsManager.netStats.fullSummary : netStatsManager.netStats.shortSummary
                    )
                } else {
                    Image(systemName: "network")
                }
            }
        )
        .menuBarExtraStyle(.window)
        
        // Scene 2: The Settings Window
        Window("Settings", id: "settings-window") {
            SettingsView() // Replace with your actual Settings View
                .environmentObject(settings)
                .frame(minWidth: 300, minHeight: 400) // Set reasonable defaults
        }
        .windowResizability(.contentSize) // Optional: locks size to content
        .defaultPosition(.center) // Optional: centers on screen
    }
    
}
