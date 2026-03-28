//
//  NetStatsViewModel.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-29.
//

import SwiftUI

class NetStatsViewModel {
    
    var netStats: NetworkStats
    var privateIP: String?
    var publicIP: String?
    
    @Environment(\.colorScheme) var colorScheme
    
    init(netStats: NetworkStats, privateIP: String?, publicIP: String?) {
        self.netStats = netStats
        self.privateIP = privateIP
        self.publicIP = publicIP
    }
    
    var isDarkModeEnabled: Bool {
        colorScheme == .dark
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
