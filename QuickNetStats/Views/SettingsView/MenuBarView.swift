//
//  MenuBarView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-12.
//

import SwiftUI

struct MenuBarView: View {
    
    @ObservedObject var settings:Settings
    
    var body: some View {
        Form {
            Section {
                ToggleView(title: "Show Summary", variable: settings.$showSummary, description: "Display a summary of the connection or just an icon")
            } header: {
                Text("Menu Bar Style")
            }
            
            Section {
                ToggleView(title: "Launch at Login", variable: .constant(false))
                
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
