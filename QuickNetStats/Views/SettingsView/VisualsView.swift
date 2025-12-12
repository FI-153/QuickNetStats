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
        Text("Visuals")
    }
}

#Preview {
    VisualsView(settings: Settings())
}
