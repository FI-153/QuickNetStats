//
//  Settings.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-13.
//

import Foundation
import SwiftUI
import Combine

class Settings:ObservableObject {
    
    enum UserDefaultsKeys {
        static let showSummaryInMenu = "showSummaryInMenu"
        static let showQualityInMenu = "showQualityInMenu"
        static let useAnimations = "useAnimations"
        static let isColorful = "isColorful"
    }
    
    @AppStorage(UserDefaultsKeys.showSummaryInMenu)
    var showSummaryInMenu: Bool = true
    
    @AppStorage(UserDefaultsKeys.showQualityInMenu)
    var showQualityInMenu: Bool = true
    
    @AppStorage(UserDefaultsKeys.useAnimations)
    var useAnimations: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    
    @AppStorage(UserDefaultsKeys.isColorful)
    var isColorful: Bool = true

}
