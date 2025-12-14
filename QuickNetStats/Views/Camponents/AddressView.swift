//
//  AddressView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-09.
//

import SwiftUI

struct AddressView: View {
    
    let title:String
    let value:String
    
    var body: some View {
        
        RoundedRectangle(cornerRadius: 16)
            .fill(
                Color.secondary.opacity(0.3)
            )
            .overlay(
                HStack(spacing: 2){
                    Text(title + ": ")
                        .foregroundStyle(.secondary)
                    Text(value)
                        .fontWeight(.semibold)
                }
                    .font(.title3)
            )
        .frame(width: 250, height: 50)
    }
}

#Preview("Addresses") {
    VStack(spacing: 30) {
        HStack {
            AddressView(title: "Private IP", value: "10.0.0.32")
            AddressView(title: "Public IP", value: "100.34.21.56")
        }
        
//        HStack {
//            AddressView(title: "Private IP", value: "999.999.999.999")
//            AddressView(title: "Public IP", value: "999.999.999.999")
//        }
        
        HStack {
            AddressView(title: "Private IP", value: "Unavailable")
            AddressView(title: "Public IP", value: "Unavailable")
        }

    }
}
