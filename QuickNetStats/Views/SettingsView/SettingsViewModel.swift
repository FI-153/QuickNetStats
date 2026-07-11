//
//  SettingsViewModel.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-11.
//

import Foundation
import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
        
    enum SettingsPage: String, CaseIterable, Identifiable {
        case menubar, visuals, connectionDetails, notifications, about

        var id: String { self.rawValue }

        var title: String {
            switch self {
            case .menubar: return "Menu Bar"
            case .visuals: return "Visuals"
            case .connectionDetails: return "Connection Details"
            case .about: return "About"
            case .notifications: return "Notifications"
            }
        }

        var icon: String {
            switch self {
            case .menubar: return "menubar.rectangle"
            case .visuals: return "accessibility"
            // "gauge.with.dots.needle.67percent" is SF Symbols 5 (macOS 14+); the
            // deployment target is macOS 13, so use the always-available fallback.
            case .connectionDetails: return "speedometer"
            case .about: return "info.circle"
            case .notifications: return "bell.badge"
            }
        }

        var color: Color {
            switch self {
            case .menubar: return Color.red
            case .visuals: return Color.blue
            case .connectionDetails: return Color.orange
            case .about: return Color.gray
            case .notifications: return Color.green
            }
        }
    }
    
}
