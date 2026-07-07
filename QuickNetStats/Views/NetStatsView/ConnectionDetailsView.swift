//
//  ConnectionDetailsView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-04.
//

import SwiftUI

/// The collapsible "Connection Details" dropdown shown below the IP buttons.
/// Fetches on first expand, stops live polling on collapse and on popover close.
/// On popover close the dropdown collapses, unless `Settings.keepDetailsExpanded` is enabled.
struct ConnectionDetailsView: View {

    @ObservedObject var manager: ConnectionDetailsManager
    @EnvironmentObject var settings: Settings
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            connectionDetailsButton
            
            if isExpanded {
                if let details = manager.details {
                    DetailGroupView(
                        title: "Interface",
                        rows: details.interfaceRows(
                            rateUnit: settings.interfaceRateUnit,
                            includeBSSID: settings.showNetworkNames
                        )
                    )
                    Divider()
                    DetailGroupView(title: "Addressing", rows: details.addressingRows)
                    Divider()
                    DetailGroupView(title: "DNS & DHCP", rows: details.dnsDhcpRows)
                    if !details.proxyRows.isEmpty {
                        Divider()
                        DetailGroupView(title: "Proxy", rows: details.proxyRows)
                    }
                    Divider()
                    DetailGroupView(title: "Wi-Fi", rows: details.wifiRows)
                    Divider()
                    LiveStatsSectionView(
                        isLive: manager.isLive,
                        showsWifiRows: details.wifi != nil,
                        stats: manager.liveStats,
                        liveUnit: settings.liveRateUnit,
                        wifiRateUnit: settings.wifiRateUnit,
                        onToggle: { manager.isLive ? manager.stopLive() : manager.startLive() }
                    )
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(settings.useAnimations ? .default : nil, value: isExpanded)
        .task(id: isExpanded) {
            if isExpanded && manager.details == nil {
                await manager.fetchDetails()
            }
            // Auto-start Live Stats on expand when the user opted in; startLive()
            // itself no-ops if polling is already running.
            if isExpanded && settings.startLiveMonitoringOnOpen {
                manager.startLive()
            }
        }
        .onDisappear {
            manager.stopLive()
            if !settings.keepDetailsExpanded {
                isExpanded = false
            }
        }
    }
    
    var connectionDetailsButton: some View {
        Button {
            isExpanded.toggle()
            if !isExpanded { manager.stopLive() }
        } label: {
            connectionDetailsLabel
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
    
    var connectionDetailsLabel: some View {
        HStack(spacing: 8) {
            Text("Connection Details")
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .font(.callout)
        .foregroundStyle(.secondary)

    }
}

// MARK: - Previews

#Preview("Wi-Fi (expanded)") {
    ConnectionDetailsView(manager: .preview(details: .mockWifi))
        .padding()
        .frame(width: 550, height: 1000)
        .environmentObject(Settings())
}

#Preview("Ethernet (expanded)") {
    ConnectionDetailsView(manager: .preview(details: .mockEthernet))
        .padding()
        .frame(width: 550, height: 1000)
        .environmentObject(Settings())
}

#Preview("VPN (expanded)") {
    ConnectionDetailsView(manager: .preview(details: .mockVPN))
        .padding()
        .frame(width: 550, height: 1000)
        .environmentObject(Settings())
}

#Preview("Loading") {
    ConnectionDetailsView(manager: .preview(details: nil))
        .padding()
        .frame(width: 550, height: 1000)
        .environmentObject(Settings())
}

#Preview("Live") {
    ConnectionDetailsView(manager: .preview(details: .mockWifi, isLive: true, liveStats: .mockLiveWifi))
        .padding()
        .frame(width: 550, height: 1000)
        .environmentObject(Settings())
}
