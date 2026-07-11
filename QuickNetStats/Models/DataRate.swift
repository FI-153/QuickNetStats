//
//  DataRate.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-06.
//

import Foundation

/// The unit family used to display a data rate. Its `rawValue` is the base-unit
/// abbreviation so it can be stored directly via `@AppStorage`.
enum RateUnit: String, CaseIterable, Identifiable {
    case bitsPerSecond = "bps"
    case bytesPerSecond = "B/s"

    var id: String { rawValue }

    /// Human-readable label for pickers, naming the family and a sample multiple.
    var displayName: String {
        switch self {
        case .bitsPerSecond: return "Bits per second (Mbps)"
        case .bytesPerSecond: return "Bytes per second (MB/s)"
        }
    }
}

/// Shared bits <-> bytes conversion and auto-scaling rate formatting. Single
/// source of truth for the customizable Connection Details units: a rate is
/// stored in its native family and converted only for display.
enum DataRate {

    // MARK: - Conversion

    /// Bits per second to bytes per second (÷ 8).
    static func bitsToBytes(_ bitsPerSecond: Double) -> Double { bitsPerSecond / 8 }

    /// Bytes per second to bits per second (× 8).
    static func bytesToBits(_ bytesPerSecond: Double) -> Double { bytesPerSecond * 8 }

    // MARK: - Formatting

    /// Formats a bits-per-second rate, displayed in `unit`. When `unit` is
    /// `.bytesPerSecond` the value is converted (÷ 8) before scaling.
    static func text(bitsPerSecond: Double, in unit: RateUnit) -> String {
        switch unit {
        case .bitsPerSecond:
            return scaled(bitsPerSecond, units: bitUnits)
        case .bytesPerSecond:
            return scaled(bitsToBytes(bitsPerSecond), units: byteUnits)
        }
    }

    /// Formats a bytes-per-second rate, displayed in `unit`. When `unit` is
    /// `.bitsPerSecond` the value is converted (× 8) before scaling.
    static func text(bytesPerSecond: Double, in unit: RateUnit) -> String {
        switch unit {
        case .bytesPerSecond:
            return scaled(bytesPerSecond, units: byteUnits)
        case .bitsPerSecond:
            return scaled(bytesToBits(bytesPerSecond), units: bitUnits)
        }
    }

    // MARK: - Private

    private static let bitUnits = ["bps", "Kbps", "Mbps", "Gbps"]
    private static let byteUnits = ["B/s", "KB/s", "MB/s", "GB/s"]

    /// Scales `value` (in the base unit of `units`) down through base-1000 multiples
    /// to the largest multiple ≥ 1, then renders it with up to two decimals and any
    /// trailing zeros stripped ("866 Mbps", "1 Gbps", "2.5 Gbps", "26.25 MB/s").
    private static func scaled(_ value: Double, units: [String]) -> String {
        var magnitude = value
        var index = 0
        while magnitude >= 1_000, index < units.count - 1 {
            magnitude /= 1_000
            index += 1
        }
        return "\(trimmed(magnitude)) \(units[index])"
    }

    /// Rounds to at most two decimals and strips trailing zeros (and a dangling
    /// decimal point), so whole values render without a fractional part.
    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded(.towardZero) {
            return String(Int(rounded))
        }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
