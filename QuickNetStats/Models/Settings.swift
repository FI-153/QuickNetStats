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
        static let showSummary = "showSummary"
        static let useAnimations = "useAnimations"
    }
    
    @AppStorage(UserDefaultsKeys.showSummary)
    var showSummary: Bool = true
    
    @AppStorage(UserDefaultsKeys.useAnimations)
    var useAnimations: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

}
