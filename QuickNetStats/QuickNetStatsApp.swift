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
    
    @State var isSettingViewOpened: Bool = false
    
    @StateObject var settings:Settings = Settings()
    
    var body: some Scene {
        MenuBarExtra( content: {
            ZStack {
                VStack(spacing: 16){
                    ContentView(
                        netStats: netStatsManager.netStats,
                        privateIP: netDetailsManager.privateIP,
                        publicIP: netDetailsManager.publicIP
                    )
                    Divider()
                    footerButtonsSection
                }
                .blur(radius: isSettingViewOpened ? 3 : 0)
                .disabled(isSettingViewOpened)
                
                SettingsView(isSettingViewOpened: $isSettingViewOpened)
                    .animation(.bouncy(duration:0.4), value: isSettingViewOpened)
                    .offset(y: isSettingViewOpened ? 0 : 500)

            }
            .padding()
            .frame(width: 550)
            .task {
                await netDetailsManager.getAddresses()
            }
            .environmentObject(settings)

        }, label: {
            if settings.showSummary {
                Text(netStatsManager.netStats.summary)
            } else {
                Image(systemName: "network")
            }
         }
        )
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
                self.isSettingViewOpened = true
            } label: {
                FooterButtonLabelView(labelText: "Settings", systemName: "gear")
            }

        }
        .buttonStyle(.plain)
        .focusable(false)

    }

}
