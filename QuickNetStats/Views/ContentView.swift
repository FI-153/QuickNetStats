//
//  ContentView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-29.
//

import SwiftUI

struct ContentView: View {
    
    @ObservedObject var netStatsManager: NetworkStatsManager
    @ObservedObject var netDetailsManager: NetworkDetailsManager
    @ObservedObject var connectionDetailsManager: ConnectionDetailsManager

    @EnvironmentObject var settings: Settings
    
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismiss) var dismiss

    /// Measured total popover height, passed down so the Connection Details cap
    /// can budget from the real chrome instead of a constant.
    @State private var popoverHeight: CGFloat = 0

    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0){
            NetStatsView(
                netStats: netStatsManager.netStats,
                privateIP: netDetailsManager.privateIP,
                publicIP: netDetailsManager.publicIP,
                ssid: netDetailsManager.ssid,
                connectionDetailsManager: connectionDetailsManager,
                popoverHeight: popoverHeight
            )

            Divider()

            footerButtonsSection
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            let rounded = height.rounded()
            if popoverHeight != rounded { popoverHeight = rounded }
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
                dismiss()
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
                guard !isRefreshing else { return }
                isRefreshing = true
                defer { isRefreshing = false }
                let minimumEnd = ContinuousClock.now.advanced(by: .seconds(1))
                netStatsManager.refresh()
                await netDetailsManager.deleteAndGetAddresses()
                await connectionDetailsManager.refresh()
                // A fast refresh would otherwise flash the disabled state.
                try? await Task.sleep(until: minimumEnd, clock: .continuous)
            }
        } label: {
            Image(systemName: "arrow.trianglehead.counterclockwise")
                .resizable()
                .fontWeight(.semibold)
                .scaledToFit()
                .frame(width: 20)
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .help("Refresh")
        .accessibilityLabel("Refresh")
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
    ContentView(
        netStatsManager: NetworkStatsManager(),
        netDetailsManager: NetworkDetailsManager(),
        connectionDetailsManager: ConnectionDetailsManager()
    )
    .environmentObject(Settings())
    .frame(height: 350)
}
