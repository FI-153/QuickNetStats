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

    func copyToClipboard(_ str: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(str, forType: .string)
    }
    
}
