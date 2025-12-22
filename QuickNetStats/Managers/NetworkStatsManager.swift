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
                
                NotificationsManager.shared.checkForNotifications(
                    oldStats: self.netStats,
                    newStats: newStats
                )
                
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
