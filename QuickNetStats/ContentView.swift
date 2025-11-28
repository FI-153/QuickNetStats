//
//  ContentView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-07.
//

import SwiftUI
import AppKit

struct ContentView: View {
    
    var netStats:NetworkStats
    var privateIP:String?
    var publicIP:String?
    @EnvironmentObject var settings:Settings
    
    var linkQualityColor: Color {
        switch netStats.linkQuality {
        case .good:
            return Color.green
        case .moderate:
            return Color.orange
        case .minimal:
            return Color.red
        default:
            return Color.secondary
        }
    }
    
        
    var body: some View {
        VStack(spacing: 16) {
            HStack (alignment: .center, spacing: 40){
                NetworkInterfaceView(
                    netIntervaceType: netStats.interfaceType,
                    isAvailable: netStats.isConnected,
                    linkQualityColor: settings.isColorful ? linkQualityColor : .primary
                )
                .frame(height: 80)
                
                if let linkQuality = netStats.linkQuality {
                    LinkQualityView(
                        linkQuality: linkQuality,
                        linkQualityColor: settings.isColorful ? linkQualityColor : .primary
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
            if netStats.isExpensive || netStats.isConstrained {
                Divider()
                
                if netStats.isExpensive {
                    Text("You are connected to a cellular connection which may have a network cap.")
                        .foregroundStyle(.secondary)
                }
                
                if netStats.isConstrained {
                    Text("Low Data Mode is anabled for this network.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
        
    var ipButtonsSection: some View {
        HStack(spacing: 16) {
            Button {
                if let publicIP = publicIP {
                    copyToClipboard(publicIP)
                }
            } label: {
                AddressView(title: "Public IP", value: publicIP ?? "Unavailbable")
            }
            .help("Click to copy to Clipboard")
            
            Button {
                if let privateIP = privateIP {
                    copyToClipboard(privateIP)
                }
            } label: {
                AddressView(title: "Private IP", value: privateIP ?? "Unavailbable")
            }
            .help("Click to copy to Clipboard")
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

func copyToClipboard(_ str :String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(str, forType: .string)
}

#Preview("Good Connection") {
    ContentView(
        netStats: NetworkStats.mockGoodWifiCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
}

#Preview("Moderate Connection") {
    ContentView(
        netStats: NetworkStats.mockModerateWifiCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Bad Connection") {
    ContentView(
        netStats: NetworkStats.mockBadWifiCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Good Eth Connection") {
    ContentView(
        netStats: NetworkStats.mockGoodEthCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Constrained") {
    ContentView(
        netStats: NetworkStats.mockConstrainedWifiCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}

#Preview("Constriied + Expansive") {
    ContentView(
        netStats: NetworkStats.mockConstrainedAndExpansiveCellCoonection,
        privateIP: "10.0.0.32",
        publicIP: "100.10.30.2"
    )
    .padding()
    .frame(width: 550)
    .environmentObject(Settings())
}


#Preview("Disconnected") {
    ContentView(
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
        ContentView(
            netStats: NetworkStats.mockGoodWifiCoonection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2"
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
        
        ContentView(
            netStats: NetworkStats.mockModerateWifiCoonection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2"
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
        
        ContentView(
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
        ContentView(
            netStats: NetworkStats.mockConstrainedWifiCoonection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2"
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
        
        ContentView(
            netStats: NetworkStats.mockExpansiveCellCoonection,
            privateIP: "10.0.0.32",
            publicIP: "100.10.30.2"
        )
        .padding()
        .frame(width: 550)
        .environmentObject(Settings())
        
        
    }
}
