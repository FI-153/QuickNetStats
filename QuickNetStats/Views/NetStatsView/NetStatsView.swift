//
//  NetStatsView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-07.
//

import SwiftUI
import AppKit
import Network

struct NetStatsView: View {
    
    @EnvironmentObject var settings: Settings
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var connectionDetailsManager: ConnectionDetailsManager

    var vm: NetStatsViewModel

    init(
        netStats: NetworkStats,
        privateIP: String?,
        publicIP: String?,
        ssid: String? = nil,
        connectionDetailsManager: ConnectionDetailsManager
    ) {
        self.vm = NetStatsViewModel(netStats: netStats, privateIP: privateIP, publicIP: publicIP, ssid: ssid)
        self.connectionDetailsManager = connectionDetailsManager
    }

    /// Icon tint used when colorful mode is off: readable in both appearances.
    private var monochromeColor: Color {
        colorScheme == .dark ? .secondary : .black
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack (alignment: .center, spacing: 40){
                VStack(spacing: 6) {
                    NetworkInterfaceView(
                        netInterfaceType: vm.netStats.interfaceType,
                        isAvailable: vm.netStats.isConnected,
                        linkQualityColor: settings.isColorful ? vm.linkQualityColor : monochromeColor
                    )

                    if settings.showNetworkNames, vm.isWifiConnection, let ssid = vm.ssid {
                        Text(ssid)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(height: 90)

                if let linkQuality = vm.netStats.linkQuality {
                    LinkQualityView(
                        linkQuality: linkQuality,
                        linkQualityColor: settings.isColorful ? vm.linkQualityColor : monochromeColor
                    )
                }
            }
            
            ipButtonsSection
            
            exceptionDescriptionSection

            if vm.netStats.isConnected {
                ConnectionDetailsView(manager: connectionDetailsManager)
            }


        }
        .padding()
    }
    
    var exceptionDescriptionSection: some View {
        return Group {
            if vm.netStats.isExpensive || vm.netStats.isConstrained {
                Divider()
                
                if vm.netStats.isExpensive {
                    Text("Your cellular connection may have a **network cap**.")
                    
                    if vm.netStats.connectionTechnology == .wifi {
                        Text("**Wireless** connection to the hotspot.")
                    } else {
                        Text("**Wired** connection to the hotspot.")
                    }
                }
                
                if vm.netStats.isConstrained {
                    Text("**Low Data Mode** is enabled for this network.")
                }
                
                Divider()
            }
        }
        .foregroundStyle(.secondary)
    }
        
    var ipButtonsSection: some View {
        HStack(spacing: 16) {
            Button {
                if let publicIP = vm.publicIP {
                    vm.copyToClipboard(publicIP)
                }
            } label: {
                AddressView(title: "Public IP", value: vm.publicIP ?? "Unavailable")
            }
            .help("Click to copy to Clipboard")
            
            Button {
                if let privateIP = vm.privateIP {
                    vm.copyToClipboard(privateIP)
                }
            } label: {
                AddressView(title: "Private IP", value: vm.privateIP ?? "Unavailable")
            }
            .help("Click to copy to Clipboard")
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - Previews

#Preview("Good Connection") {
    NetStatsView(
        netStats: NetworkStats.mockGoodWifiConnection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2",
        ssid: "HomeNet 5GHz",
        connectionDetailsManager: .preview(details: .mockWifi)
    )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
}

#Preview("Moderate Connection") {
    NetStatsView(
        netStats: NetworkStats.mockModerateWifiConnection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2",
        connectionDetailsManager: .preview(details: .mockWifi)
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Bad Connection") {
    NetStatsView(
        netStats: NetworkStats.mockBadWifiConnection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2",
        connectionDetailsManager: .preview(details: .mockWifi)
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Good Eth Connection") {
    NetStatsView(
        netStats: NetworkStats.mockGoodEthConnection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2",
        connectionDetailsManager: .preview(details: .mockEthernet)
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Constrained") {
    NetStatsView(
        netStats: NetworkStats.mockConstrainedWifiConnection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2",
        connectionDetailsManager: .preview(details: .mockWifi)
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Constriied + Expensive") {
    NetStatsView(
        netStats: NetworkStats.mockConstrainedExpensiveCellConnection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2",
        connectionDetailsManager: .preview(details: .mockWifi)
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Disconnected") {
    NetStatsView(
        netStats: NetworkStats.mockDisconnected,
        privateIP: nil,
        publicIP: nil,
        connectionDetailsManager: .preview(details: nil)
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("QuickNetStats") {
    VStack {
        NetStatsView(
            netStats: NetworkStats.mockGoodWifiConnection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2",
            connectionDetailsManager: .preview(details: .mockWifi)
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())

        NetStatsView(
            netStats: NetworkStats.mockModerateWifiConnection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2",
            connectionDetailsManager: .preview(details: .mockWifi)
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())

        NetStatsView(
            netStats: NetworkStats.mockBadWifiConnection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2",
            connectionDetailsManager: .preview(details: .mockWifi)
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())

    }
}

#Preview("Constrained or Expensive Connections") {
    HStack(spacing: 100) {
        NetStatsView(
            netStats: NetworkStats.mockConstrainedWifiConnection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2",
            connectionDetailsManager: .preview(details: .mockWifi)
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())

        NetStatsView(
            netStats: NetworkStats.mockExpensiveCellConnection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2",
            connectionDetailsManager: .preview(details: .mockEthernet)
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())

    }
}
