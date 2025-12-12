//
//  AboutView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-12.
//

import SwiftUI

struct AboutView: View {
    
    @ObservedObject var settings:Settings
    
    var body: some View {
        Text("About")
    }
}

#Preview {
    AboutView(settings: Settings())
}
