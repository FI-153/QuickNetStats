//
//  NetStatsViewModel.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-29.
//

import SwiftUI
import Network

class NetStatsViewModel {
    
    var netStats: NetworkStats
    var privateIP: String?
    var publicIP: String?
    var ssid: String?

    init(netStats: NetworkStats, privateIP: String?, publicIP: String?, ssid: String? = nil) {
        self.netStats = netStats
        self.privateIP = privateIP
        self.publicIP = publicIP
        self.ssid = ssid
    }

    /// True when the SSID label is meaningful: the active connection actually rides Wi-Fi.
    var isWifiConnection: Bool {
        netStats.interfaceType == .wifi || netStats.connectionTechnology == .wifi
    }

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

    /// Icon tint used when colorful mode is off: readable in both appearances.
    static func monochromeColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .secondary : .primary
    }

    /// Single spoken description of the hero icon and link-quality indicator for VoiceOver.
    func accessibilitySummary(includeSSID: Bool) -> String {
        guard netStats.isConnected else { return "Disconnected" }
        var parts = [spokenInterfaceName]
        if includeSSID, isWifiConnection, let ssid { parts.append(ssid) }
        if let quality = netStats.linkQuality, quality != .unknown {
            parts.append("link quality \(quality.description)")
        }
        return parts.joined(separator: ", ")
    }

    private var spokenInterfaceName: String {
        switch netStats.interfaceType {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .cellular: return "Personal Hotspot"
        default: return "Network"
        }
    }

}
