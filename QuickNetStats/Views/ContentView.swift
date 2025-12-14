//
//  ContentView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-29.
//

import SwiftUI

struct ContentView: View {
    
    @ObservedObject var netStatsManager:NetworkStatsManager
    @ObservedObject var netDetailsManager:NetworkDetailsManager
    
    @EnvironmentObject var settings:Settings
    
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        VStack(spacing: 0){
            NetStatsView(
                netStats: netStatsManager.netStats,
                privateIP: netDetailsManager.privateIP,
                publicIP: netDetailsManager.publicIP
            )
            
            Divider()
            
            footerButtonsSection
        }
        
    }
    
    var footerButtonsSection: some View {
        return HStack(spacing: 40) {            
            Button {
                Task {
                    netStatsManager.refresh()
                    await netDetailsManager.deleteAndGetAddresses()
                }
            } label: {
                FooterButtonLabelView(labelText: "Refresh", systemName: "arrow.trianglehead.counterclockwise")
            }
            
            Button {
                openWindow(id: "settings-window")
            } label: {
                FooterButtonLabelView(labelText: "Settings", systemName: "gear")
            }

        }
        .buttonStyle(.plain)
        .focusable(false)
        .padding(.top)
    }

}

#Preview {
    ContentView(netStatsManager: NetworkStatsManager(), netDetailsManager: NetworkDetailsManager())
        .environmentObject(Settings())
        .frame(height: 350)
}
