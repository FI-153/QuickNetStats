//
//  CommandLineManager.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-07.
//

import Foundation
import Network
import Combine

class NetworkStatsManager: ObservableObject {

    private var monitor: NWPathMonitor

    /// A dedicated queue for the monitor to run on to avoid blocking the main thread.
    private let queue: DispatchQueue

    /// Status of the connection where True means connected and able to send data and False means disconnected.
    @Published var netStats: NetworkStats

    /// Track if the monitor is monitoring to avoid multiple monitoring sessions.
    private var isMonitoring: Bool

    /// Track if it is the first update to avoid sending notifications on launch
    private var isFirstUpdate: Bool

    /// The reachability checker used to verify internet connectivity.
    private let reachabilityChecker: InternetReachabilityChecking

    /// Tracks the in-flight reachability check so it can be cancelled on new path updates.
    private var reachabilityTask: Task<Void, Never>?

    /// Tracks the polling loop task so it can be cancelled on disconnect or stop.
    private var pollingTask: Task<Void, Never>?

    init(reachabilityChecker: InternetReachabilityChecking = InternetReachabilityChecker()) {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.quickconncheck.networkMonitor")
        self.netStats = NetworkStats.defaultOffline
        self.isMonitoring = false
        self.isFirstUpdate = true
        self.reachabilityChecker = reachabilityChecker
        startMonitoring()
    }

    // MARK: - Monitoring

    /// Start monitoring network path changes.
    func startMonitoring() {
        guard !isMonitoring else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.handlePathUpdate(path)
            }
        }

        monitor.start(queue: queue)
        self.isMonitoring = true
    }

    /// Stop monitoring network path changes.
    private func stopMonitoring() {
        guard self.isMonitoring else { return }

        self.isMonitoring = false
        reachabilityTask?.cancel()
        stopPolling()
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

    // MARK: - Path Handling

    /// Processes a path update from NWPathMonitor, gating on reachability when connected.
    private func handlePathUpdate(_ path: NWPath) {
        let pathStats = NetworkStats(path: path)

        // Cancel any in-flight reachability check
        reachabilityTask?.cancel()

        guard pathStats.isConnected else {
            // Path says disconnected — publish immediately, stop polling
            stopPolling()
            publishStats(pathStats)
            return
        }

        // Path says connected — verify with reachability check
        reachabilityTask = Task {
            let reachable = await reachabilityChecker.checkReachability()
            guard !Task.isCancelled else { return }

            if reachable {
                self.publishStats(pathStats)
                self.startPolling()
            } else {
                self.publishStats(NetworkStats.defaultOffline)
                self.stopPolling()
            }
        }
    }

    /// Publishes new stats, sending notifications unless this is the first update.
    private func publishStats(_ newStats: NetworkStats) {
        if isFirstUpdate {
            isFirstUpdate = false
            netStats = newStats
            return
        }

        NotificationsManager.shared.checkForNotifications(
            oldStats: netStats,
            newStats: newStats
        )
        netStats = newStats
    }

    // MARK: - Polling

    /// Starts the 15-second periodic reachability polling loop.
    private func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await pollReachability()
            }
        }
    }

    /// Stops the periodic polling loop.
    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Runs a single reachability check from the polling loop.
    private func pollReachability() async {
        let reachable = await reachabilityChecker.checkReachability()
        guard !Task.isCancelled else { return }

        if !reachable {
            publishStats(NetworkStats.defaultOffline)
            stopPolling()
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
