//
//  VisualsView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-12.
//

import SwiftUI

struct VisualsView: View {
    
    @ObservedObject var settings: Settings
    
    var body: some View {
        Form {
            Section {
                ToggleView(
                    title: "Use Animations",
                    variable: settings.$useAnimations
                )
                
                ToggleView(
                    title: "Colorful Mode",
                    variable: settings.$isColorful,
                    description: "Use colors that change according to the quality of the network"
                )

                ToggleView(
                    title: "Keep Details Expanded",
                    variable: settings.$keepDetailsExpanded,
                    description: "Keep the Connection Details section expanded after the menu bar closes"
                )
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
