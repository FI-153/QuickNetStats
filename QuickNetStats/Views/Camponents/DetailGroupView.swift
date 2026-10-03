//
//  DetailGroupView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-04.
//

import SwiftUI

/// A titled two-column grid of label–value rows for one connection-details group.
/// Each value is a ``CopyButton`` that copies its raw string to the clipboard.
/// Renders nothing when `rows` is empty.
struct DetailGroupView: View {

    let title: String
    let rows: [DetailRow]
    var animated = true

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                detailsTitle
                
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.leading)

                            CopyButton(value: row.value, animated: animated) { isConfirming in
                                Group {
                                    if isConfirming {
                                        Label("Copied", systemImage: "checkmark")
                                    } else {
                                        Text(row.value)
                                            .monospacedDigit()
                                            .truncationMode(.middle)
                                    }
                                }
                                .lineLimit(1)
                                .accessibilityLabel(row.value)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var detailsTitle: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Previews

#Preview("Populated") {
    DetailGroupView(title: "Interface", rows: ConnectionDetails.mockWifi.interfaceRows)
        .padding()
        .frame(width: 300)
}

#Preview("Empty (renders nothing)") {
    DetailGroupView(title: "Interface", rows: [])
        .padding()
        .frame(width: 300)
}

#Preview("Long value truncates") {
    DetailGroupView(
        title: "Addressing",
        rows: [DetailRow(label: "IPv6 (local)", value: "2a00:1450:4009:82b:0000:0000:0000:200e")]
    )
    .padding()
    .frame(width: 300)
}
