//
//  CommandLineManager.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-07.
//

import Foundation
import Network
import Combine

class NetworkStatsManager:ObservableObject {
    
    private var monitor: NWPathMonitor
    
    /// A dedicated queue for the monitor to run on to avoid blocking the main thread.
    private let queue: DispatchQueue
    
    /// Status of the connection where True means connected and able to send data and False means disconnected.
    @Published var netStats: NetworkStats
    
    /// Track if the monitor is monitoring to avoid multiple monitoring sessions.
    private var isMonitoring:Bool
    
    /// Track if it is the first update to avoid sending notifications on launch
    private var isFirstUpdate:Bool
    
    init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.quickconncheck.networkMonitor")
        self.netStats = NetworkStats.defaultOffline
        self.isMonitoring = false
        self.isFirstUpdate = true
        startMonitoring()
    }
        
    /// Start monitoring network path changes.
    func startMonitoring() {
        
        // Prevent starting a monitor when it has already started
        guard !isMonitoring else { return }
        
        monitor.pathUpdateHandler = { [weak self] path in
            
            // Update the published netStats property on the main thread
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                let newStats = NetworkStats(path: path)
                
                if self.isFirstUpdate {
                    self.isFirstUpdate = false
                    self.netStats = newStats
                    return
                }
                
                self.checkForNotifications(oldStats: self.netStats, newStats: newStats)
                self.netStats = newStats
            }
        }
        
        // Start the monitor on background queue
        monitor.start(queue: queue)
        
        self.isMonitoring = true
    }
    
    /// Stop monitoring network path changes
    private func stopMonitoring() {
        
        // Prevent stopping a monitor that has not started
        guard self.isMonitoring else { return }
        
        self.isMonitoring = false
        self.netStats = NetworkStats.defaultOffline
        
        // Cancel the monitor
        monitor.cancel()
        
        // Initialize a new monitor since every monitor can only be started once
        // and further start instructions are ignored
        monitor = NWPathMonitor()
    }
    
    /// Refresh the monitor by stopping the current one and starting a new monitor.
    func refresh() {
        stopMonitoring()
        startMonitoring()
    }
    
    /// Checks if a notification should be sent based on the change in network statistics
    private func checkForNotifications(oldStats: NetworkStats, newStats: NetworkStats) {
        let defaults = UserDefaults.standard
        
        // Check if notifications are globally enabled
        guard defaults.bool(forKey: Settings.UserDefaultsKeys.isNotificationActive) else { return }
        
        // Internet Connection Status Changes
        let internetNotificationsBehavior = InternetNotificationBehavior(
            rawValue: defaults.integer(forKey: Settings.UserDefaultsKeys.notifyInternetBehavior)
        ) ?? .connects
        
        let wasConnected = oldStats.isConnected
        let isConnected = newStats.isConnected
        
        if wasConnected != isConnected {
            var shouldNotify = false
            var title = ""
            var body = ""
            
            switch internetNotificationsBehavior {
            case .connects:
                if isConnected {
                    shouldNotify = true
                    title = "Internet Connected"
                    body = "You are now connected to \(newStats.interfaceType.rawValue)"
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
                    body = "You are now connected to \(newStats.interfaceType.rawValue)"
                } else {
                    title = "Internet Disconnected"
                    body = "You are now disconnected from the internet"
                }
            }
            
            if shouldNotify {
                NotificationsManager.shared.notify(titled: title, body)
            }
        }
        
        // Link Quality Changes
        let liknQualityNotificationsBehavior = LinkQualityNotificationBehavior(
            rawValue: defaults
                .integer(
                    forKey: Settings.UserDefaultsKeys.notifyQualityBehavior
                )
        ) ?? .changes
        
        let oldQuality = oldStats.linkQuality?.rawValue ?? 0
        let newQuality = newStats.linkQuality?.rawValue ?? 0
        
        if oldQuality != newQuality {
            var shouldNotify = false
            var title = ""
            var body = ""
            
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
                NotificationsManager.shared.notify(titled: title, body)
            }
        }

        
        // Notify on Interface Change if enabled
        if defaults.bool(forKey: Settings.UserDefaultsKeys.notifyInterfaceChanges) {
             if wasConnected && isConnected && oldStats.interfaceType != newStats.interfaceType {
                 NotificationsManager.shared.notify(
                    titled: "Network Changed",
                    "Switched to \(newStats.interfaceType.rawValue)"
                 )
             }
        }
    }
    
    deinit {
        stopMonitoring()
    }
}

import Playgrounds
#Playground {
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "com.quickconncheck.networkMonitor")
    var netStats = NetworkStats.defaultOffline
    
    monitor.pathUpdateHandler = { path in
        
        // Check the path's status
        let connected = (path.status == .satisfied)
        
        // Update the @Published property on the main thread
        DispatchQueue.main.async {
            netStats = NetworkStats(path: path)
            
            print(path.status)
            print("reason: \(path.unsatisfiedReason)")
            print("wifi?: \(path.usesInterfaceType(.wifi))")
            print("eth?: \(path.usesInterfaceType(.wiredEthernet))")
            print("constrained?: \(path.isConstrained)")
            print("expansive?: \(path.isExpensive)")
            if #available(macOS 26, *) {
                print("quality: \(path.linkQuality)")
            }
        }
    }
    
    // Start the monitor on background queue
    monitor.start(queue: queue)
    
}
