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
    
    private let monitor: NWPathMonitor
    
    // A dedicated queue for the monitor to run on to avoid blocking the main thread
    private let queue: DispatchQueue
    
    /// Status of the connection where True means connected and able to send data and False means disconnected
    @Published var netStats: NetworkStats
    
    private var isMonitoring:Bool
    
    init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.quickconncheck.networkMonitor")
        self.netStats = NetworkStats.defaultOffline
        self.isMonitoring = false
        startMonitoring()
    }
    
    init(netStats:NetworkStats) {
        self.netStats = netStats
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.quickconncheck.networkMonitor")
        self.isMonitoring = false
    }
    
    /**
     * Starts monitoring network path changes.
     */
    func startMonitoring() {
        
        guard !isMonitoring else { return }
        
        monitor.pathUpdateHandler = { [weak self] path in
            
            // Update the @Published property on the main thread
            DispatchQueue.main.async {
                self?.netStats = NetworkStats(path: path)
            }
        }
        
        // Start the monitor on background queue
        monitor.start(queue: queue)
        self.isMonitoring = true
    }
    
    /**
     * Stops monitoring network path changes.
     */
    private func stopMonitoring() {
        
        guard self.isMonitoring else { return }
        
        self.isMonitoring = false
        monitor.cancel()
    }
    
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
            print("quality: \(path.linkQuality)")
        }
    }
    
    // Start the monitor on background queue
    monitor.start(queue: queue)
    
}
