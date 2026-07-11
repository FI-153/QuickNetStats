//
//  WifiReader.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-04.
//

import Foundation
import CoreWLAN

/// A read-only snapshot of Wi-Fi RF/PHY facts for one interface.
struct WifiSnapshot: Equatable {
    var channelNumber: Int?
    var band: String?
    var channelWidthMHz: Int?
    var phyMode: String?
    var interfaceMode: String?   // "Station" | "IBSS" | "Host AP"
    var txPowerMw: Int?
    var security: String?
    var countryCode: String?
    var rssiDBm: Int?
    var noiseDBm: Int?
    var txRateMbps: Double?
    var bssid: String?
}

/// A seam over CoreWLAN so the manager stays testable.
protocol WifiReading {
    func snapshot(for bsdName: String) -> WifiSnapshot?
    /// The SSID of the default Wi-Fi interface; nil off Wi-Fi or when Location
    /// Services authorization is missing.
    func currentSSID() -> String?
}

/// Reads channel/band/width/PHY/security and RF metrics from CoreWLAN. Returns
/// `nil` for non-Wi-Fi interfaces or when Wi-Fi is off. This is the ONLY file that
/// imports CoreWLAN. **`ssid()`/`bssid()` are read here (the sole exception to the
/// project-wide prohibition); they return nil without Location Services
/// authorization — see `LocationPermissionManager`.**
///
/// Enum fields are mapped by `rawValue` rather than by Swift-imported case names,
/// which sidesteps the fragile acronym casing of `CWSecurity` (`.WEP`/`.OWE`) and
/// degrades any unknown/future value to `nil` (row omitted) instead of crashing.
struct WifiReader: WifiReading {

    /// Builds a Wi-Fi snapshot for the given BSD interface name, or nil if it is
    /// not a Wi-Fi interface / Wi-Fi is unavailable.
    func snapshot(for bsdName: String) -> WifiSnapshot? {
        guard let interface = CWWiFiClient.shared().interface(withName: bsdName) else {
            return nil
        }

        var snapshot = WifiSnapshot()

        if let channel = interface.wlanChannel() {
            snapshot.channelNumber = channel.channelNumber
            snapshot.band = Self.bandText(channel.channelBand.rawValue)
            snapshot.channelWidthMHz = Self.widthMHz(channel.channelWidth.rawValue)
        }

        snapshot.phyMode = Self.phyModeText(interface.activePHYMode().rawValue)
        snapshot.interfaceMode = Self.modeText(interface.interfaceMode().rawValue)
        snapshot.security = Self.securityText(interface.security().rawValue)
        snapshot.countryCode = interface.countryCode()

        // CoreWLAN reports 0 mW when transmit power is unavailable; treat as nil.
        let txPower = interface.transmitPower()
        snapshot.txPowerMw = txPower > 0 ? txPower : nil

        // CoreWLAN reports 0 dBm when RSSI/noise are unavailable; treat as nil.
        let rssi = interface.rssiValue()
        snapshot.rssiDBm = rssi == 0 ? nil : rssi
        let noise = interface.noiseMeasurement()
        snapshot.noiseDBm = noise == 0 ? nil : noise

        let txRate = interface.transmitRate()
        snapshot.txRateMbps = txRate > 0 ? txRate : nil

        // Location-gated: nil without Location Services authorization (graceful).
        snapshot.bssid = interface.bssid()

        return snapshot
    }

    /// The SSID of the default Wi-Fi interface, or nil off Wi-Fi / when Location
    /// Services authorization is missing (CoreWLAN returns nil, never prompts).
    func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    // MARK: - Enum mapping (by rawValue)

    /// Maps `CWChannelBand` raw values to a display string; unknown/future → nil.
    private static func bandText(_ rawValue: Int) -> String? {
        switch rawValue {
        case 1: return "2.4 GHz"
        case 2: return "5 GHz"
        case 3: return "6 GHz"
        default: return nil          // kCWChannelBandUnknown (0) and future values
        }
    }

    /// Maps `CWChannelWidth` raw values to a width in MHz; unknown/future → nil.
    private static func widthMHz(_ rawValue: Int) -> Int? {
        switch rawValue {
        case 1: return 20
        case 2: return 40
        case 3: return 80
        case 4: return 160
        default: return nil          // kCWChannelWidthUnknown (0) and future values
        }
    }

    /// Maps `CWInterfaceMode` raw values to a display string; none (0)/future → nil.
    static func modeText(_ rawValue: Int) -> String? {
        switch rawValue {
        case 1: return "Station"
        case 2: return "IBSS"
        case 3: return "Host AP"
        default: return nil          // kCWInterfaceModeNone (0) and future values
        }
    }

    /// Maps `CWPHYMode` raw values to an IEEE 802.11 name; none/future → nil.
    private static func phyModeText(_ rawValue: Int) -> String? {
        switch rawValue {
        case 1: return "802.11a"
        case 2: return "802.11b"
        case 3: return "802.11g"
        case 4: return "802.11n"
        case 5: return "802.11ac"
        case 6: return "802.11ax"
        case 7: return "802.11be"
        default: return nil          // kCWPHYModeNone (0) and future values
        }
    }

    /// `CWSecurity` raw value → display string. `13` is WPA3 Transition
    /// (WPA3/WPA2). Any value absent here (e.g. `kCWSecurityUnknown` = NSIntegerMax
    /// or a future case) maps to nil, so the row degrades to omitted.
    private static let securityNames: [Int: String] = [
        0: "Open",
        1: "WEP",
        2: "WPA Personal",
        3: "WPA/WPA2 Personal",
        4: "WPA2 Personal",
        5: "Personal",
        6: "Dynamic WEP",
        7: "WPA Enterprise",
        8: "WPA/WPA2 Enterprise",
        9: "WPA2 Enterprise",
        10: "Enterprise",
        11: "WPA3 Personal",
        12: "WPA3 Enterprise",
        13: "WPA2/WPA3 Personal",
        14: "OWE",
        15: "OWE Transition"
    ]

    /// Maps `CWSecurity` raw values to a display string; unknown/future → nil.
    private static func securityText(_ rawValue: Int) -> String? {
        securityNames[rawValue]
    }
}
