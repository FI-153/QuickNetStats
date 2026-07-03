//
//  NetworkStatsManager.swift
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

    /// Track if it is the first update to avoid sending notifications on launch. Internal for testing.
    var isFirstUpdate: Bool

    /// The latest connected snapshot reported by the path. Cleared when the path
    /// goes down or monitoring stops. Drives poll-based recovery. Internal for testing.
    var lastPathStats: NetworkStats?

    /// The reachability checker used to verify internet connectivity.
    private let reachabilityChecker: InternetReachabilityChecking

    /// Tracks the in-flight reachability check so it can be cancelled on new path updates.
    private var reachabilityTask: Task<Void, Never>?

    /// Tracks the polling loop task so it can be cancelled on disconnect or stop.
    private var pollingTask: Task<Void, Never>?

    init(
        reachabilityChecker: InternetReachabilityChecking = InternetReachabilityChecker(),
        autoStart: Bool = true
    ) {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.quickconncheck.networkMonitor")
        self.netStats = NetworkStats.defaultOffline
        self.isMonitoring = false
        self.isFirstUpdate = true
        self.reachabilityChecker = reachabilityChecker
        if autoStart {
            startMonitoring()
        }
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
        lastPathStats = nil
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

        // stopMonitoring resets netStats to offline; treat the next publish as a
        // baseline so the restart doesn't fire a spurious "connected" notification.
        isFirstUpdate = true

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
            lastPathStats = nil
            publishStats(pathStats)
            return
        }

        // Path says connected — verify with reachability check
        lastPathStats = pathStats
        reachabilityTask = Task { [weak self] in
            guard let self else { return }
            let reachable = await self.reachabilityChecker.checkReachability()
            guard !Task.isCancelled else { return }

            self.publishStats(reachable ? pathStats : NetworkStats.defaultOffline)

            // Keep polling while the path is satisfied so recovery is detected
            // even when the probe failed (e.g. the router lost upstream).
            self.startPolling()
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
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { break }
                await self.pollReachability()
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
        applyPollResult(reachable: reachable)
    }

    /// Publishes stats for a poll result, only on connectivity transitions so
    /// repeated identical results don't re-publish. Internal for testing.
    func applyPollResult(reachable: Bool) {
        guard let pathStats = lastPathStats else { return }

        if reachable && !netStats.isConnected {
            publishStats(pathStats)
        } else if !reachable && netStats.isConnected {
            publishStats(NetworkStats.defaultOffline)
        }
    }

    deinit {
        stopMonitoring()
    }
}
