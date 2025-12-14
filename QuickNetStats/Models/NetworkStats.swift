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
    
    /// The technology underlying the connection (Allows to distinguish between wired and wireless cellular).
    let connectionTechnology:NWInterface.InterfaceType
    
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
        
        // Only show the quality for macOS 26+
        var quality = ""
        if #available(macOS 26, *) {
            if let linkQuality = linkQuality {
                if linkQuality != .unknown {
                    quality = "\(linkQuality.rawValue.capitalized)"
                }
            }
        }
        
        return "\(quality) \(interfaceType.rawValue.capitalized) Connection"
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
            self.unsatisfiedReason = path.unsatisfiedReason
        } else {
            self.unsatisfiedReason = nil
        }
        
        if path.usesInterfaceType(.wifi) {
            
            // The technology is Wifi: this is a wireless network
            self.connectionTechnology = .wifi
            
            // A wireless connection to an hotspot still registers as WiFi
            // Set it to cellular for greater clarity
            self.interfaceType = path.isExpensive ? .cellular : .wifi
            
        } else if path.usesInterfaceType(.cellular) {
            self.connectionTechnology = .cellular
            self.interfaceType = .cellular
            
        } else if path.usesInterfaceType(.wiredEthernet) {
            
            // The technology is Ethernet: this is a wired network
            self.connectionTechnology = .wiredEthernet
            
            // A wired connection to an hotspot still registers as Ethernet
            // Set it to cellular for greater clarity
            self.interfaceType = path.isExpensive ? .cellular : .ethernet
            
        } else if path.status == .satisfied {
            
            // Connected, but not a known type
            self.connectionTechnology = .other
            self.interfaceType = .other
            
        } else {
            // Not connected
            self.connectionTechnology = .other
            self.interfaceType = .none
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
    
    // Use this for mockups and static defaults
    private init(status: NWPath.Status,
                 interfaceType: NetworkInterfaceType,
                 isExpensive: Bool,
                 isConstrained: Bool,
                 reason: NWPath.UnsatisfiedReason?,
                 linkQuality:LinkQuality,
                 connectionTechnology:NWInterface.InterfaceType
    ) {
        
        self.status = status
        self.interfaceType = interfaceType
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.unsatisfiedReason = reason
        self.linkQuality = linkQuality
        self.connectionTechnology = connectionTechnology
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
            linkQuality: .unknown,
            connectionTechnology: .other
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
            linkQuality: .good,
            connectionTechnology: .wifi
        )
    }
    
    static var mockModerateWifiCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .wifi,
            isExpensive: false,
            isConstrained: false,
            reason: .none,
            linkQuality: .moderate,
            connectionTechnology: .wifi
        )
    }
    
    static var mockBadWifiCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .wifi,
            isExpensive: false,
            isConstrained: false,
            reason: .none,
            linkQuality: .minimal,
            connectionTechnology: .wifi
        )
    }
    
    static var mockGoodEthCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .ethernet,
            isExpensive: false,
            isConstrained: false,
            reason: .none,
            linkQuality: .good,
            connectionTechnology: .wiredEthernet
        )
    }
    
    static var mockConstrainedWifiCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .wifi,
            isExpensive: false,
            isConstrained: true,
            reason: .none,
            linkQuality: .good,
            connectionTechnology: .wifi
        )
    }
    
    static var mockConstrainedAndExpansiveCellCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .cellular,
            isExpensive: true,
            isConstrained: true,
            reason: .none,
            linkQuality: .good,
            connectionTechnology: .wifi
        )
    }
    
    static var mockExpansiveCellCoonection: NetworkStats {
        return NetworkStats(
            status: .satisfied,
            interfaceType: .cellular,
            isExpensive: true,
            isConstrained: false,
            reason: .none,
            linkQuality: .good,
            connectionTechnology: .wiredEthernet
        )
    }
    
    static var mockDisconnected: NetworkStats {
        return NetworkStats(
            status: .unsatisfied,
            interfaceType: .none,
            isExpensive: false,
            isConstrained: false,
            reason: .notAvailable,
            linkQuality: .unknown,
            connectionTechnology: .other
        )
    }


}
