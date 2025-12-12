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
        
        VStack {
            NavigationSplitView {
                List(SettingsViewModel.SettingsPage.allCases, selection: $selectedPage) { page in
                    NavigationLink(value: page) {
                        settingsListItem(page)
                    }
                }
                .navigationSplitViewColumnWidth(min: 150, ideal: 200)
                
            } detail: {
                switch selectedPage {
                case .menubar:
                    MenuBarView(settings: settings)
                case .visuals:
                    VisualsView(settings: settings)
                case .about:
                    AboutView(settings: settings)
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .navigationTitle(selectedPage.title)
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
    
    fileprivate func toggleSection(_ title:String, _ variable: Binding<Bool>) -> some View {
        return HStack{
            Text(title)
                .fontWeight(.semibold)
            
            Spacer()
            
            Toggle(isOn: variable) {}
                .toggleStyle(.switch)
        }
        .frame(width: 350)
    }
            
}

#Preview("Settings") {
    SettingsView()
        .environmentObject(Settings())
}
