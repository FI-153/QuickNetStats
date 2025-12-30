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
        .overlay(alignment: .topTrailing) {
            headerButtonsSection
        }
        
    }
    
    var footerButtonsSection: some View {
        return HStack(spacing: 40) {            
            Button {
                openNetworkSettings()
            } label: {
                FooterButtonLabelView(labelText: "Network Settings", systemName: "network")
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
    
    var headerButtonsSection: some View {
        Button {
            Task {
                netStatsManager.refresh()
                await netDetailsManager.deleteAndGetAddresses()
            }
        } label: {
            Image(systemName: "arrow.trianglehead.counterclockwise")
                .resizable()
                .fontWeight(.semibold)
                .scaledToFit()
                .frame(width: 20)
        }
        .buttonStyle(.plain)
        .padding(.trailing)
    }
    
    private func openNetworkSettings() {
        let urlString = "x-apple.systempreferences:com.apple.Network"
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

}

#Preview {
    ContentView(netStatsManager: NetworkStatsManager(), netDetailsManager: NetworkDetailsManager())
        .environmentObject(Settings())
        .frame(height: 350)
}
