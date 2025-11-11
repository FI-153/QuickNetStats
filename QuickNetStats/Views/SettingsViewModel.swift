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
    @Binding var isSettingViewOpened: Bool

    init(isSettingViewOpened: Binding<Bool>) {
        self._isSettingViewOpened = isSettingViewOpened
    }
}
