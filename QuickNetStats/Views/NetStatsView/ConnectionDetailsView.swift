//
//  ConnectionDetailsView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-04.
//

import SwiftUI
import AppKit

/// The collapsible "Connection Details" dropdown shown below the IP buttons.
/// Fetches on first expand, stops live polling on collapse and on popover close.
/// On popover close the dropdown collapses, unless `Settings.keepDetailsExpanded` is enabled.
struct ConnectionDetailsView: View {

    @ObservedObject var manager: ConnectionDetailsManager
    @EnvironmentObject var settings: Settings
    @State private var isExpanded = false

    var popoverHeight: CGFloat = 0

    private static let fallbackMaxDetailsHeight: CGFloat = 600
    
    /// Gap kept between the popover and the menu bar when budgeting by visible height.
    private static let detailsMargin: CGFloat = 16
    
    private static let minimumDetailsHeight: CGFloat = 100

    @State private var detailsContentHeight: CGFloat = .infinity
    
    /// Rendered height of the details scroll view itself. Subtracted from
    /// ``popoverHeight`` to derive the popover chrome (icon block, IP buttons,
    /// exception text, buttons, footer, paddings).
    @State private var scrollRenderedHeight: CGFloat = 0

    private var chromeHeight: CGFloat? {
        guard popoverHeight > 0, scrollRenderedHeight > 0 else { return nil }
        return (popoverHeight - scrollRenderedHeight).rounded()
    }

    /// The scroll-view height cap for the expanded details. Read per body
    /// evaluation via `NSScreen.main` (the screen containing the key window — the
    /// MenuBarExtra panel is key while the popover is open), so reopening the
    /// popover on a different display picks up that screen's metrics.
    private var maxDetailsHeight: CGFloat {
        Self.maxDetailsHeight(
            screenHeight: NSScreen.main?.frame.height,
            visibleHeight: NSScreen.main?.visibleFrame.height,
            chromeHeight: chromeHeight
        )
    }

    /// Bounds the details cap by, in order of precedence.
    /// Returns the smaller of the applicable bounds.
    static func maxDetailsHeight(
        screenHeight: CGFloat?,
        visibleHeight: CGFloat?,
        chromeHeight: CGFloat?
    ) -> CGFloat {
        guard let screenHeight else { return fallbackMaxDetailsHeight }
        
        let userBound = screenHeight * 0.75
        guard let visibleHeight, let chromeHeight, chromeHeight > 0 else { return userBound }
        
        let fitBound = max(minimumDetailsHeight, visibleHeight - chromeHeight - detailsMargin)
        return min(userBound, fitBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            connectionDetailsButton
            
            if isExpanded {
                if let details = manager.details {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            detailsContentHeight = height
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: min(detailsContentHeight, maxDetailsHeight))
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        let rounded = height.rounded()
                        if scrollRenderedHeight != rounded { scrollRenderedHeight = rounded }
                    }
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
