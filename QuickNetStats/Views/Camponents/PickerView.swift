//
//  PickerView.swift
//  QuickNetStats
//
//  Created by Gemini on 2025-12-22.
//

import SwiftUI

struct PickerView<SelectionValue: Hashable, Content: View>: View {
    
    let title: String
    let selection: Binding<SelectionValue>
    var description: String?
    var isDisabled: Bool?
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        Picker(selection: selection) {
            content()
        } label: {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.body)
                
                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .pickerStyle(.menu)
        .disabled(isDisabled ?? false)
    }
}

#Preview {
    VStack {
        Form {
            PickerView(title: "Notify when the internet", selection: .constant(0)) {
                Text("Connects").tag(0)
                Text("Disconnects").tag(1)
                Text("Changes").tag(2)
            }
            .padding()
        }
        
        Form {
            PickerView(
                title: "Notify when the internet",
                selection: .constant(0),
                description: "blalalalal"
            ) {
                Text("Connects").tag(0)
                Text("Disconnects").tag(1)
                Text("Changes").tag(2)
            }
            .padding()
        }

        
        Form {
            PickerView(
                title: "Notify when the internet",
                selection: .constant(0),
                isDisabled: true
            ) {
                Text("Connects").tag(0)
                Text("Disconnects").tag(1)
                Text("Changes").tag(2)
            }
            .padding()
        }
    }
}
