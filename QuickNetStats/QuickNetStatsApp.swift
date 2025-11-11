//
//  QuickNetStatsApp.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-07.
//

import SwiftUI

@main
struct QuickNetStatsApp: App {
    
    @StateObject var netStatsManager:NetworkStatsManager = NetworkStatsManager()
    @StateObject var netDetailsManager:NetworkDetailsManager = NetworkDetailsManager()
    
    var body: some Scene {
        MenuBarExtra(content: {
            VStack(spacing: 16){
                ContentView(
                    netStats: netStatsManager.netStats,
                    privateIP: netDetailsManager.privateIP,
                    publicIP: netDetailsManager.publicIP
                )
                Divider()
                footerButtonsSection
            }
            .padding()
            .frame(width: 550)
            .task {
                await netDetailsManager.getAddresses()
            }

        }, label: {
            HStack(alignment: .center) {
                Text(netStatsManager.netStats.isConnected ? "Connected" : "Disconnected")
                Label("Quick Net Stas", systemImage: "network")
            }
        })
        .menuBarExtraStyle(.window)
    }
    
    var footerButtonsSection: some View {
        return HStack(spacing: 40) {
            Button {
                exit(0)
            } label: {
                FooterButtonLabelView(labelText: "Quit", systemName: "power")
            }
            
            Button {
                Task {
                    netStatsManager.refresh()
                    await netDetailsManager.getAddresses()
                }
            } label: {
                FooterButtonLabelView(labelText: "Refresh", systemName: "arrow.trianglehead.counterclockwise")
            }
            
            Button {
                
            } label: {
                FooterButtonLabelView(labelText: "Settings", systemName: "gear")
            }

        }
        .buttonStyle(.plain)

    }

}
