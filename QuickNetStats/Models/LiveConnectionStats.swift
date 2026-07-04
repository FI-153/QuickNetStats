//
//  LiveConnectionStats.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-04.
//

import Foundation

/// One live sample of throughput and Wi-Fi RF metrics, published by
/// `ConnectionDetailsManager` while the popover's Live section is active.
/// Throughput fields stay `nil` until the second poll tick (a counter delta is
/// needed); RF fields are `nil` on non-Wi-Fi interfaces.
struct LiveConnectionStats: Equatable {

    // MARK: - Properties

    var downloadBytesPerSec: Double?
    var uploadBytesPerSec: Double?
    var rssiDBm: Int?
    var noiseDBm: Int?
    var txRateMbps: Double?

    // MARK: - Computed Properties

    /// Signal-to-noise ratio in dB: `rssi − noise` when both are present.
    var snrDB: Int? {
        guard let rssiDBm, let noiseDBm else { return nil }
        return rssiDBm - noiseDBm
    }

    var rssiText: String? { rssiDBm.map { "\($0) dBm" } }
    var noiseText: String? { noiseDBm.map { "\($0) dBm" } }
    var snrText: String? { snrDB.map { "\($0) dB" } }
    var txRateText: String? { txRateMbps.map { ConnectionDetails.linkSpeedText($0) } }
    var downloadText: String? { downloadBytesPerSec.map { Self.rateText($0) } }
    var uploadText: String? { uploadBytesPerSec.map { Self.rateText($0) } }

    // MARK: - Formatters

    /// Formats a byte-per-second rate with a magnitude-appropriate unit.
    /// Whole bytes below 1 KB/s; one decimal for KB/s and above. Uses the C
    /// locale (`String(format:)`) so the output is deterministic and testable.
    static func rateText(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1_000 {
            return "\(Int(bytesPerSec.rounded())) B/s"
        } else if bytesPerSec < 1_000_000 {
            return String(format: "%.1f KB/s", bytesPerSec / 1_000)
        } else if bytesPerSec < 1_000_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
        } else {
            return String(format: "%.1f GB/s", bytesPerSec / 1_000_000_000)
        }
    }

    // MARK: - Mockups

    /// A live Wi-Fi sample with throughput and RF metrics.
    static let mockLiveWifi = LiveConnectionStats(
        downloadBytesPerSec: 1_200_000,
        uploadBytesPerSec: 340_000,
        rssiDBm: -52,
        noiseDBm: -95,
        txRateMbps: 866
    )

    /// A live wired sample with throughput only.
    static let mockLiveWired = LiveConnectionStats(
        downloadBytesPerSec: 8_500_000,
        uploadBytesPerSec: 1_100_000
    )
}
