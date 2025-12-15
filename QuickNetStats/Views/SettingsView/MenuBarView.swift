//
//  MenuBarView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-12.
//

import SwiftUI

struct MenuBarView: View {
    
    @ObservedObject var settings:Settings
    @StateObject private var launchManager = LaunchAtLoginManager()
    
    var body: some View {
        Form {
            Section {
                ToggleView(title: "Show Summary", variable: settings.$showSummaryInMenu, description: "Display a summary of the connection or just an icon")
                ToggleView(title: "Show Network quality", variable: settings.$showQualityInMenu, description: "Display a description of the network quality or not")
            } header: {
                Text("Menu Bar Style")
            }
            
            Section {
                ToggleView(
                    title: "Launch at Login",
                    variable: Binding(
                        get: { launchManager.isEnabled },
                        set: { _ in launchManager.toggle() }
                    )
                )
            } header: {
                Text("System Features")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    MenuBarView(settings: Settings())
}
