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
        Text("Menu Bar")
    }
}

#Preview {
    MenuBarView(settings: Settings())
}
