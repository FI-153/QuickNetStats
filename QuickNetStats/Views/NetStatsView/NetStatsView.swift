//
//  ContentView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-07.
//

import SwiftUI
import AppKit
import Network

struct NetStatsView: View {
    
    @EnvironmentObject var settings:Settings
    
    var vm:NetStatsViewModel
    
    init(netStats:NetworkStats, privateIP:String?, publicIP:String?) {
        self.vm = NetStatsViewModel(netStats: netStats, privateIP: privateIP, publicIP: publicIP)
    }
        
    var body: some View {
        VStack(spacing: 16) {
            HStack (alignment: .center, spacing: 40){
                NetworkInterfaceView(
                    netIntervaceType: vm.netStats.interfaceType,
                    isAvailable: vm.netStats.isConnected,
                    linkQualityColor: settings.isColorful ? vm.linkQualityColor : vm.isDarkModeEnabled ? .secondary : .black
                )
                .frame(height: 80)
                
                if let linkQuality = vm.netStats.linkQuality {
                    LinkQualityView(
                        linkQuality: linkQuality,
                        linkQualityColor: settings.isColorful ? vm.linkQualityColor : vm.isDarkModeEnabled ? .secondary : .black
                    )
                }
            }
            
            ipButtonsSection

            exceptionDescriptionSection
                        
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

//MARK - Previews

#Preview("Good Connection") {
    NetStatsView(
        netStats: NetworkStats.mockGoodWifiCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
}

#Preview("Moderate Connection") {
    NetStatsView(
        netStats: NetworkStats.mockModerateWifiCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Bad Connection") {
    NetStatsView(
        netStats: NetworkStats.mockBadWifiCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Good Eth Connection") {
    NetStatsView(
        netStats: NetworkStats.mockGoodEthCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Constrained") {
    NetStatsView(
        netStats: NetworkStats.mockConstrainedWifiCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Constriied + Expansive") {
    NetStatsView(
        netStats: NetworkStats.mockConstrainedAndExpansiveCellCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}


#Preview("Disconnected") {
    NetStatsView(
        netStats: NetworkStats.mockDisconnected,
        privateIP: nil,
        publicIP: nil
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("QuickNetStats") {
    VStack {
        NetStatsView(
            netStats: NetworkStats.mockGoodWifiCoonection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2"
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
        
        NetStatsView(
            netStats: NetworkStats.mockModerateWifiCoonection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2"
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
        
        NetStatsView(
            netStats: NetworkStats.mockBadWifiCoonection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2"
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
        
    }
}

#Preview("Constrained or Expansive Connections") {
    HStack(spacing: 100) {
        NetStatsView(
            netStats: NetworkStats.mockConstrainedWifiCoonection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2"
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
        
        NetStatsView(
            netStats: NetworkStats.mockExpansiveCellCoonection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2"
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
        
        
    }
}
