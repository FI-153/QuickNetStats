//
//  AddressView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-09.
//

import SwiftUI

struct AddressView: View {

    let title: String
    let value: String
    /// Swaps the value for a "Copied" confirmation.
    var isConfirming = false

    private var pillShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(title + ": ")
                .foregroundStyle(.secondary)

            Group {
                if isConfirming {
                    Label("Copied", systemImage: "checkmark")
                } else {
                    Text(value)
                        .truncationMode(.middle)
                }
            }
            .fontWeight(.semibold)
        }
        .font(.title3)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(pillShape.fill(Color.secondary.opacity(0.3)))
        .contentShape(pillShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

#Preview("Addresses") {
    VStack(spacing: 30) {
        HStack(spacing: 16) {
            AddressView(title: "Private IP", value: "10.0.0.32")
            AddressView(title: "Public IP", value: "100.34.21.56")
        }

        HStack(spacing: 16) {
            AddressView(title: "Private IP", value: "10.0.0.32", isConfirming: true)
            AddressView(title: "Public IP", value: "2a00:1450:4009:82b::200e")
        }

        HStack(spacing: 16) {
            AddressView(title: "Private IP", value: "Unavailable")
            AddressView(title: "Public IP", value: "Unavailable")
        }

    }
    .padding()
    .frame(width: 550)
}
