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

    /// True when launched with `--demo`: every manager is seeded with fixed mock
    /// data for promotional screenshots and never reads or fetches real network
    /// state. Fake values can be overridden per launch through the volatile
    /// defaults argument domain (never persisted), e.g.
    /// `open QuickNetStats.app --args --demo -demoSSID "HomeNet" -showNetworkNames 1`.
    private static let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")

    /// Demo public IP; a documentation address (TEST-NET-3) so screenshots can
    /// never leak a real one. Override with `-demoPublicIP`.
    private static var demoPublicIP: String {
        UserDefaults.standard.string(forKey: "demoPublicIP") ?? "203.0.113.42"
    }

    /// Demo private IP. Override with `-demoPrivateIP`.
    private static var demoPrivateIP: String {
        UserDefaults.standard.string(forKey: "demoPrivateIP") ?? "192.168.1.42"
    }

    /// Demo Wi-Fi name shown under the icon (requires `-showNetworkNames 1`).
    /// Override with `-demoSSID`.
    private static var demoSSID: String {
        UserDefaults.standard.string(forKey: "demoSSID") ?? "Federico's Wi-Fi"
    }

    @StateObject var netStatsManager: NetworkStatsManager = QuickNetStatsApp.makeNetStatsManager()
    @StateObject var netDetailsManager: NetworkDetailsManager = QuickNetStatsApp.makeNetworkDetailsManager()
    @StateObject var connectionDetailsManager: ConnectionDetailsManager = QuickNetStatsApp.makeConnectionDetailsManager()
    @StateObject var settings: Settings = Settings()

    let notificationDelegate = NotificationDelegate()

    /// The live path monitor normally; in demo mode a stopped monitor pinned to
    /// the mock Wi-Fi snapshot so the menu bar label stays stable.
    private static func makeNetStatsManager() -> NetworkStatsManager {
        guard isDemo else { return NetworkStatsManager() }
        let manager = NetworkStatsManager(autoStart: false)
        manager.netStats = .mockGoodWifiConnection
        return manager
    }

    /// The real address fetcher normally; in demo mode pre-seeded with the fake
    /// addresses (the demo `.task` branch below never calls `getAddresses()`).
    private static func makeNetworkDetailsManager() -> NetworkDetailsManager {
        let manager = NetworkDetailsManager()
        if isDemo {
            manager.publicIP = demoPublicIP
            manager.privateIP = demoPrivateIP
            manager.ssid = demoSSID
        }
        return manager
    }

    /// The real details manager normally; in demo mode pre-populated with the
    /// mock dropdown, Live armed on static stats.
    private static func makeConnectionDetailsManager() -> ConnectionDetailsManager {
        guard isDemo else { return ConnectionDetailsManager() }
        return .preview(details: .mockWifi, isLive: true, liveStats: .mockLiveWifi)
    }

    /// Restores the demo state on each popover appearance: closing the popover
    /// stops Live (clearing the mock stats), and the refresh button may have
    /// overwritten the fake values with real ones.
    private func applyDemoState() {
        netStatsManager.netStats = .mockGoodWifiConnection
        netDetailsManager.publicIP = Self.demoPublicIP
        netDetailsManager.privateIP = Self.demoPrivateIP
        netDetailsManager.ssid = Self.demoSSID
        connectionDetailsManager.apply(details: .mockWifi, isLive: true, liveStats: .mockLiveWifi)
    }
    
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
                    // In demo mode nothing live is wired: no change observation and
                    // no address fetch, or real values would overwrite the fakes.
                    guard !Self.isDemo else {
                        applyDemoState()
                        return
                    }
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
