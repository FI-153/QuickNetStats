//
//  VisualsView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-12.
//

import SwiftUI

struct VisualsView: View {
    
    @ObservedObject var settings:Settings
    
    var body: some View {
        Form {
            Section {
                ToggleView(title: "Use Animations", variable: settings.$showSummary)
                ToggleView(title: "Monotone Mode", variable: settings.$isColorful, description: "Use colors that change according to the quality of the network")
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    VisualsView(settings: Settings())
}
