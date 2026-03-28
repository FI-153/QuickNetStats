//
//  FooterButtonView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-09.
//

import SwiftUI

struct FooterButtonLabelView: View {
    
    let labelText: String
    let systemName: String
    
    var body: some View {
        Label {
            Text(labelText)
                .font(.system(size: 14, weight: .semibold))
        } icon: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
        }
    }
}

#Preview {
    HStack {
        FooterButtonLabelView(labelText: "Quit", systemName: "power")
            .padding(.horizontal)
        
        FooterButtonLabelView(labelText: "Refresh", systemName: "arrow.trianglehead.counterclockwise")
            .padding(.horizontal)

        FooterButtonLabelView(labelText: "Settings", systemName: "gear")
            .padding(.horizontal)
    }
    .padding()
}
