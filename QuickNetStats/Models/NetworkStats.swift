//
//  NetworkStats.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-07.
//

import Foundation

import Foundation
import Network

enum NetworkInterfaceType: String {
    case wifi = "Wifi"
    case cellular = "Cellular"
    case ethernet = "Ethernet"
    case other = "Other"
    case none = "None"
}

enum LinkQuality: String {
    case good, moderate, minimal, unknown
}

struct NetworkStats {
    
    // MARK: - Properties
    
    /// The overall status of the network path.
    let status: NWPath.Status
    
    /// The primary interface type (e.g., Wi-Fi, Cellular).
    let interfaceType: NetworkInterfaceType
    
    /// True if the network is considered "expensive" (e.g., cellular data cap).
    let isExpensive: Bool
    
    /// True if the user has enabled "Low Data Mode".
    let isConstrained: Bool
    
    /// If status is .unsatisfied, this provides the reason.
    let unsatisfiedReason: NWPath.UnsatisfiedReason?
    
    /// Returns the qualirty of the connection
    var linkQuality:LinkQuality?
    
    // MARK: - Computed Properties
    
    var isConnected: Bool {
        return status == .satisfied
    }
    
    /// Summarizes the state of the connection in a sentence that can be shown to the user
    var summary:String {
        
        if interfaceType == .none {
            return "No Connection"
        }
        
        var quality = ""
        if #available(macOS 26, *) {
            if let linkQuality = linkQuality {
                if linkQuality != .unknown {
                    quality = "\(linkQuality.rawValue.capitalized) "
                }
            }
        }
        
        return "\(quality)Connection to \(interfaceType.rawValue.capitalized)"
    }
    
    // MARK: - Initializers
    
    /**
     * Creates a new NetworkStats snapshot from an NWPath object.
     */
    init(path: NWPath) {
        self.status = path.status
        self.isExpensive = path.isExpensive
        self.isConstrained = path.isConstrained
        
        if path.status == .unsatisfied {
            
            if #available(iOS 14.2, *) {
                self.unsatisfiedReason = path.unsatisfiedReason
            } else {
                self.unsatisfiedReason = .notAvailable // Best guess for older OS
            }
        } else {
            self.unsatisfiedReason = nil
        }
        
        if path.usesInterfaceType(.wifi) {
            self.interfaceType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            self.interfaceType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            self.interfaceType = .ethernet
        } else if path.status == .satisfied {
            self.interfaceType = .other // Connected, but not a known type
        } else {
            self.interfaceType = .none // Not connected
        }
        
        
        if #available(macOS 26, *) {
            switch path.linkQuality {
            case .minimal:
                self.linkQuality = .minimal
            case .moderate:
                self.linkQuality = .moderate
            case .good:
                self.linkQuality = .good
            default:
                self.linkQuality = .unknown
            }
        }
        
    }
    
    private init(status: NWPath.Status,
                 interfaceType: NetworkInterfaceType,
                 isExpensive: Bool,
                 isConstrained: Bool,
                 reason: NWPath.UnsatisfiedReason?,
                 linkQuality:LinkQuality) {
        
        self.status = status
        self.interfaceType = interfaceType
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.unsatisfiedReason = reason
        self.linkQuality = linkQuality
    }
    
    // MARK: - Static Default
    
    /**
     * Provides a default "offline" state to use when the monitor
     * first starts
     */
    static var defaultOffline: NetworkStats {
        return NetworkStats(
            status: .unsatisfied,
            interfaceType: .none,
            isExpensive: false,
            isConstrained: false,
            reason: .notAvailable,
            linkQuality: .unknown
        )
    }
    
    // MARK: - Mockups
    static var mockGoodWifiCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .wifi,
            isExpensive: false,
            isConstrained: false,
            reason: .none,
            linkQuality: .good
        )
    }
    
    static var mockModerateWifiCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .wifi,
            isExpensive: false,
            isConstrained: false,
            reason: .none,
            linkQuality: .moderate
        )
    }
    
    static var mockBadWifiCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .wifi,
            isExpensive: false,
            isConstrained: false,
            reason: .none,
            linkQuality: .minimal
        )
    }
    
    static var mockGoodEthCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .ethernet,
            isExpensive: false,
            isConstrained: false,
            reason: .none,
            linkQuality: .good
        )
    }
    
    static var mockConstrainedWifiCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .wifi,
            isExpensive: false,
            isConstrained: true,
            reason: .none,
            linkQuality: .good
        )
    }
    
    static var mockConstrainedAndExpansiveWifiCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .wifi,
            isExpensive: true,
            isConstrained: true,
            reason: .none,
            linkQuality: .good
        )
    }
    
    static var mockDisconnected: NetworkStats {
        return NetworkStats(
            status: .unsatisfied,
            interfaceType: .none,
            isExpensive: false,
            isConstrained: false,
            reason: .notAvailable,
            linkQuality: .unknown
        )
    }


}
