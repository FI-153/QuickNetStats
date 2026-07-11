//
//  LiveStatsSectionView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-04.
//

import SwiftUI

/// The always-last "Live" section of the connection-details dropdown. Idle it
/// shows grayed titles with "—" placeholders; toggled on it shows live values.
/// The toggle is delegated to the owner via `onToggle` so all polling lives in
/// the manager. Live rows are plain text (values churn every second, not copied).
struct LiveStatsSectionView: View {

    let isLive: Bool
    let showsWifiRows: Bool
    let stats: LiveConnectionStats?
    /// Unit family for the Download/Upload throughput rows.
    let liveUnit: RateUnit
    /// Unit family for the Wi-Fi Tx-rate row.
    let wifiRateUnit: RateUnit
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Live Stats")
                    .foregroundStyle(isLive ? .secondary : .tertiary)

                Spacer()

                Button(action: onToggle) {
                    Label(isLive ? "Stop Monitoring" : "Start Monitoring", systemImage: isLive ? "stop.fill" : "play.fill")
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(isLive ? "Stop monitoring live metrics" : "Start monitoring live metrics")
            }
            .font(.title2)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                liveRow("Download", stats?.downloadText(in: liveUnit))
                liveRow("Upload", stats?.uploadText(in: liveUnit))
                // Packet/error/drop counters are interface-agnostic, like throughput.
                liveRow("Packets ↓", stats?.downloadPacketsText)
                liveRow("Packets ↑", stats?.uploadPacketsText)
                liveRow("Errors", stats?.errorsText)
                liveRow("Drops", stats?.dropsText)

                if showsWifiRows {
                    liveRow("RSSI", stats?.rssiText)
                    liveRow("Noise", stats?.noiseText)
                    liveRow("SNR", stats?.snrText)
                    liveRow("Tx rate", stats?.txRateText(in: wifiRateUnit))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One label–value grid row. Idle: both cells grayed with a "—" value.
    /// Live: secondary label, primary value; a momentarily missing value stays "—".
    @ViewBuilder
    private func liveRow(_ label: String, _ value: String?) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(isLive ? .secondary : .tertiary)
                .gridColumnAlignment(.leading)

            Text(isLive ? (value ?? "—") : "—")
                .monospacedDigit()
                .foregroundStyle(isLive ? .primary : .tertiary)
        }
    }
}

// MARK: - Previews

#Preview("Idle Wi-Fi") {
    LiveStatsSectionView(
        isLive: false,
        showsWifiRows: true,
        stats: nil,
        liveUnit: .bytesPerSecond,
        wifiRateUnit: .bitsPerSecond,
        onToggle: {}
    )
    .padding()
    .frame(width: 300)
}

#Preview("Live Wi-Fi") {
    LiveStatsSectionView(
        isLive: true,
        showsWifiRows: true,
        stats: .mockLiveWifi,
        liveUnit: .bytesPerSecond,
        wifiRateUnit: .bitsPerSecond,
        onToggle: {}
    )
    .padding()
    .frame(width: 300)
}

#Preview("Live Wired") {
    LiveStatsSectionView(
        isLive: true,
        showsWifiRows: false,
        stats: .mockLiveWired,
        liveUnit: .bytesPerSecond,
        wifiRateUnit: .bitsPerSecond,
        onToggle: {}
    )
    .padding()
    .frame(width: 300)
}
