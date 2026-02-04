//
//  Settings.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-13.
//

import Foundation
import SwiftUI
import Combine
import AppKit

enum InternetNotificationBehavior: Int, CaseIterable, Identifiable {
    case connects = 0
    case disconnects = 1
    case changes = 2
    var id: Int { rawValue }
}

enum LinkQualityNotificationBehavior: Int, CaseIterable, Identifiable {
    case worsens = 0
    case improves = 1
    case changes = 2
    var id: Int { rawValue }
}

class Settings:ObservableObject {
    
    enum UserDefaultsKeys {
        static let showSummaryInMenu = "showSummaryInMenu"
        static let showQualityInMenu = "showQualityInMenu"
        static let useAnimations = "useAnimations"
        static let isColorful = "isColorful"
        static let isNotificationActive = "isNotificationActive"
        static let notifyInternetBehavior = "notifyInternetBehavior"
        static let notifyQualityBehavior = "notifyQualityBehavior"
        static let notifyInterfaceChanges = "notifyInterfaceChanges"
    }
    
    @AppStorage(UserDefaultsKeys.showSummaryInMenu)
    var showSummaryInMenu: Bool = true
    
    @AppStorage(UserDefaultsKeys.showQualityInMenu)
    var showQualityInMenu: Bool = true
    
    @AppStorage(UserDefaultsKeys.useAnimations)
    var useAnimations: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    
    @AppStorage(UserDefaultsKeys.isColorful)
    var isColorful: Bool = true
    
    @AppStorage(UserDefaultsKeys.isNotificationActive)
    var isNotificationActive: Bool = false
    
    @AppStorage(UserDefaultsKeys.notifyInternetBehavior)
    private var notifyInternetBehaviorRaw: Int = InternetNotificationBehavior.connects.rawValue
    var notifyInternetBehavior: InternetNotificationBehavior {
        get { InternetNotificationBehavior(rawValue: notifyInternetBehaviorRaw) ?? .connects }
        set { notifyInternetBehaviorRaw = newValue.rawValue }
    }
    
    @AppStorage(UserDefaultsKeys.notifyQualityBehavior)
    private var notifyQualityBehaviorRaw: Int = LinkQualityNotificationBehavior.changes.rawValue
    var notifyQualityBehavior: LinkQualityNotificationBehavior {
        get { LinkQualityNotificationBehavior(rawValue: notifyQualityBehaviorRaw) ?? .changes }
        set { notifyQualityBehaviorRaw = newValue.rawValue }
    }
    
    @AppStorage(UserDefaultsKeys.notifyInterfaceChanges)
    var notifyInterfaceChanges: Bool = false

}
