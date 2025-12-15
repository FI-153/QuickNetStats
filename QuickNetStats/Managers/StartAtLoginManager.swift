//
//  StartAtLoginManager.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-15.
//

import SwiftUI
import ServiceManagement
import Combine

class LaunchAtLoginManager: ObservableObject {

    /// Tracks if the app is enabled to launch at login
    @Published var isEnabled: Bool
    
    init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }
    
    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            // Update state only if the OS operation succeeded
            isEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            print("Failed to toggle launch at login: \(error)")
            // Revert the UI to match the actual system state
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
