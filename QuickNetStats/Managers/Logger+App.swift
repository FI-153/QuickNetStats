//
//  Logger+App.swift
//  QuickNetStats
//

import Foundation
import os

extension Logger {
    /// Subsystem shared by all app loggers; filter on it with `log stream --predicate`.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.federicoimberti.quicknetstats"

    /// Diagnostics for raw network path updates.
    static let network = Logger(subsystem: subsystem, category: "network")

    /// Diagnostics for notification decisions.
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
