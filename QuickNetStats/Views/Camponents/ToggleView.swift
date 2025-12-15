//
//  ToggleView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-13.
//

import SwiftUI

struct ToggleView: View {
    
    let title:String
    let variable:Binding<Bool>
    var description:String?
    var isDisabled:Bool?
    
    var body: some View {
        Toggle(isOn: variable){
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
        .toggleStyle(.switch)
        .disabled(isDisabled ?? false)
    }
}

#Preview {
    VStack(alignment: .leading) {
        ToggleView(title: "Show Network Summary", variable: .constant(true))
            .padding(.horizontal)
        ToggleView(title: "Show Network Summary", variable: .constant(true), description: "Display a summary of the connection or just an icon")
            .padding(.horizontal)
    }
}
