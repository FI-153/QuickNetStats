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
    
    @State var isSettingViewOpened: Bool = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0){
                NetStatsView(
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
                .animation(settings.useAnimations ? .bouncy(duration:0.4) : .none, value: isSettingViewOpened)
                .offset(y: isSettingViewOpened ? 0 : 500)
                .environmentObject(settings)
        }
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
        .padding(.top)
    }

}

#Preview {
    ContentView(netStatsManager: NetworkStatsManager(), netDetailsManager: NetworkDetailsManager())
        .environmentObject(Settings())
        .frame(height: 350)
}
