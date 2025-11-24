//
//  NetworkInterfaceView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-09.
//

import SwiftUI

struct NetworkInterfaceView: View {
    
    let netIntervaceType:NetworkInterfaceType
    let isAvailable:Bool
    let linkQualityColor:Color
    
    @State var appear:Bool = true
    
    @EnvironmentObject var settings:Settings
        
    var symbolName: String {
        switch (netIntervaceType) {
        case .ethernet:
             return "cable.coaxial"
        case .wifi:
            return "wifi"
        case .cellular:
            return "personalhotspot"
        default:
            return "network"
        }
    }
    
    var body: some View {
        if #available(macOS 14.0, *), settings.useAnimations {
            imageSection
                .symbolEffect(.bounce, options: .speed(1.5) .nonRepeating, value: appear)
        } else {
            imageSection
        }
    }
    
    var imageSection:some View {
        
        Group {
            if isAvailable {
                Image(systemName: symbolName)
                    .resizable()
                    .foregroundStyle(linkQualityColor)
            } else {
                Image(systemName: symbolName)
                    .resizable()
                    .foregroundStyle(.gray)
                    .modifier(VerticalShimmerEffect())
            }
        }
        .symbolRenderingMode(.hierarchical)
        .scaledToFit()
        .onAppear {
            self.appear.toggle()
        }
        
    }
}

#Preview {
    VStack (spacing: 100){
        HStack(spacing: 100) {
            NetworkInterfaceView(netIntervaceType: .wifi, isAvailable: true, linkQualityColor: .green)
                .frame(height: 80)

            NetworkInterfaceView(netIntervaceType: .wifi, isAvailable: false, linkQualityColor: .secondary)
                .frame(height: 80)

        }
        HStack(spacing: 100) {
            NetworkInterfaceView(netIntervaceType: .ethernet, isAvailable: true, linkQualityColor: .green)
                .frame(height: 80)

            NetworkInterfaceView(netIntervaceType: .ethernet, isAvailable: false, linkQualityColor: .secondary)
                .frame(height: 80)

        }
        HStack(spacing: 100) {
            NetworkInterfaceView(netIntervaceType: .cellular, isAvailable: true, linkQualityColor: .green)
                .frame(height: 80)

            NetworkInterfaceView(netIntervaceType: .cellular, isAvailable: false, linkQualityColor: .secondary)
                .frame(height: 80)

        }
        HStack(spacing: 100) {
            NetworkInterfaceView(netIntervaceType: .other, isAvailable: true, linkQualityColor: .green)
                .frame(height: 80)

            NetworkInterfaceView(netIntervaceType: .other, isAvailable: false, linkQualityColor: .secondary)
                .frame(height: 80)
        }

    }
    .environmentObject(Settings())
    .padding()
}
