//
//  SettingsView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-11.
//

import SwiftUI

struct SettingsView: View {
    
    @StateObject var vm: SettingsViewModel
    @EnvironmentObject var settings:Settings
    
    @State private var selectedPage:SettingsViewModel.SettingsPage = .menubar
    
    init() {
        _vm = .init(wrappedValue: SettingsViewModel())
    }
    
    var body: some View {
        
        NavigationSplitView {
            List(SettingsViewModel.SettingsPage.allCases, selection: $selectedPage) { page in
                NavigationLink(value: page) {
                    settingsListItem(page)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 180)
        } detail: {
            switch selectedPage {
            case .menubar:
                MenuBarView(settings: settings)
            case .visuals:
                VisualsView(settings: settings)
            case .notifications:
                NotificationView(settings: settings)
            case .about:
                AboutView(settings: settings)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle(selectedPage.title)
        .toolbar {
            Button {
                exit(0)
            } label: {
                HStack {
                    Image(systemName: "power")
                        .fontWeight(.bold)
                    Text("Quit App")
                }
                .padding(8)
            }
        }
        .onAppear {
            // Show the app icon in the dock and bring the settings to the foreground
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            // Hide the app icon from the dock
            NSApp.setActivationPolicy(.accessory)
        }
        
    }
    
    fileprivate func settingsListItem(_ page:SettingsViewModel.SettingsPage) -> some View {
        HStack (alignment: .center) {
            Image(systemName: page.icon)
                .font(.title2)
                .fontWeight(.bold)
                .frame(width: 40, height: 40)
                .background(
                    page.color
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            
            Text(page.title)
                .font(.title3)
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .environmentObject(Settings())
}
