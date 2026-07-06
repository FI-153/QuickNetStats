//
//  PathReader.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-06.
//

import Foundation
import Network

/// A one-shot read of `NWPath` facts: protocol-support flags plus the other usable
/// interfaces beside the primary. Flags are optional so a timeout/loss (empty
/// snapshot) is distinguishable from a real all-false path.
struct PathSnapshot: Equatable {
    var supportsIPv4: Bool?
    var supportsIPv6: Bool?
    var supportsDNS: Bool?
    /// Other usable interfaces beside the primary, e.g. `["Ethernet (en1)"]`.
    var otherInterfaces: [String] = []
}

/// A seam over a one-shot `NWPathMonitor` so the manager stays testable.
protocol PathReading {
    func snapshot(excluding primaryBSDName: String?) async -> PathSnapshot
}

/// Reads a single `NWPath` by starting an `NWPathMonitor`, awaiting its first
/// update (delivered immediately on start), then cancelling. Races a timeout so a
/// pathological monitor can never hang `fetchDetails`; on timeout it returns an
/// empty snapshot.
struct PathReader: PathReading {

    /// Seconds to wait for the monitor's first callback before giving up.
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 2.0) {
        self.timeout = timeout
    }

    /// Returns the first `NWPath` snapshot, or an empty snapshot if the monitor
    /// does not report within `timeout`. `primaryBSDName` is excluded from
    /// `otherInterfaces`.
    func snapshot(excluding primaryBSDName: String?) async -> PathSnapshot {
        await withTaskGroup(of: PathSnapshot.self) { group in
            group.addTask { await Self.firstPath(excluding: primaryBSDName) }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return PathSnapshot()   // empty on timeout
            }
            let winner = await group.next() ?? PathSnapshot()
            group.cancelAll()           // loser resumes via onCancel / a thrown sleep
            return winner
        }
    }

    // MARK: - One-shot monitor

    /// Owns the continuation and guarantees it is resumed exactly once, whichever of
    /// the monitor's first callback or the task-cancellation handler wins — and
    /// whatever order `attach`/`resume` arrive in (a resume before attach is stashed).
    private final class ResumeGuard {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<PathSnapshot, Never>?
        private var pending: PathSnapshot?
        private var done = false

        /// Registers the continuation; delivers a stashed value if a resume already raced ahead.
        func attach(_ continuation: CheckedContinuation<PathSnapshot, Never>) {
            lock.lock()
            if done { lock.unlock(); return }
            if let value = pending {
                done = true
                pending = nil
                lock.unlock()
                continuation.resume(returning: value)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }

        /// Resumes with `value` once; if the continuation isn't attached yet, stashes it.
        func resume(with value: PathSnapshot) {
            lock.lock()
            if done { lock.unlock(); return }
            if let continuation {
                done = true
                self.continuation = nil
                lock.unlock()
                continuation.resume(returning: value)
            } else {
                pending = value
                lock.unlock()
            }
        }
    }

    /// Starts a monitor, resumes on its first path callback, and resumes with an
    /// empty snapshot on task cancellation (so a cancelled child never leaves the
    /// task group hanging when the timeout wins the race).
    private static func firstPath(excluding primaryBSDName: String?) async -> PathSnapshot {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.federicoimberti.quicknetstats.pathreader")
        let guardBox = ResumeGuard()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<PathSnapshot, Never>) in
                monitor.pathUpdateHandler = { path in
                    let snapshot = Self.snapshot(from: path, excluding: primaryBSDName)
                    monitor.cancel()
                    guardBox.resume(with: snapshot)
                }
                guardBox.attach(continuation)
                monitor.start(queue: queue)
            }
        } onCancel: {
            monitor.cancel()
            guardBox.resume(with: PathSnapshot())
        }
    }

    /// Builds a `PathSnapshot` from a live `NWPath`, formatting each non-primary,
    /// non-loopback available interface as "TypeLabel (bsdName)".
    private static func snapshot(from path: NWPath, excluding primaryBSDName: String?) -> PathSnapshot {
        var result = PathSnapshot()
        result.supportsIPv4 = path.supportsIPv4
        result.supportsIPv6 = path.supportsIPv6
        result.supportsDNS = path.supportsDNS
        result.otherInterfaces = path.availableInterfaces.compactMap { interface in
            guard interface.name != primaryBSDName,
                  let label = Self.typeLabel(interface.type) else { return nil }
            return "\(label) (\(interface.name))"
        }
        return result
    }

    /// Maps an `NWInterface.InterfaceType` to a display label; loopback is excluded
    /// entirely (nil), unknown/other → "Other".
    private static func typeLabel(_ type: NWInterface.InterfaceType) -> String? {
        switch type {
        case .wifi: return "Wi-Fi"
        case .wiredEthernet: return "Ethernet"
        case .cellular: return "Cellular"
        case .loopback: return nil
        case .other: return "Other"
        @unknown default: return "Other"
        }
    }
}
