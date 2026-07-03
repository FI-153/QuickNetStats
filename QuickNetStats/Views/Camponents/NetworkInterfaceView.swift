//
//  NetworkInterfaceView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-09.
//

import SwiftUI

struct NetworkInterfaceView: View {
    
    let netInterfaceType: NetworkInterfaceType
    let isAvailable: Bool
    let linkQualityColor: Color
    
    @State var appear: Bool = true
    
    @EnvironmentObject var settings: Settings
        
    var symbolName: String {
        switch netInterfaceType {
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
    
    var imageSection: some View {
        
        Group {
            if isAvailable {
                Image(systemName: symbolName)
                    .resizable()
                    .foregroundStyle(linkQualityColor)
            } else {
                Image(systemName: symbolName)
                    .resizable()
                    .foregroundStyle(.gray)
                    .modifier(ShimmerEffect(direction: .vertical, offset: 200))
            }
        }
        .symbolRenderingMode(.hierarchical)
        .scaledToFit()
        .onAppear {
            self.appear.toggle()
        }
        
    }
}

#Preview("Network Interface") {
    VStack (spacing: 100){
        HStack (spacing: 100){
            HStack(spacing: 30) {
                NetworkInterfaceView(netInterfaceType: .wifi, isAvailable: true, linkQualityColor: .green)
                    .frame(height: 80)
                
                NetworkInterfaceView(netInterfaceType: .wifi, isAvailable: false, linkQualityColor: .secondary)
                    .frame(height: 80)
                
            }
            HStack(spacing: 30) {
                NetworkInterfaceView(netInterfaceType: .ethernet, isAvailable: true, linkQualityColor: .green)
                    .frame(height: 80)
                
                NetworkInterfaceView(netInterfaceType: .ethernet, isAvailable: false, linkQualityColor: .secondary)
                    .frame(height: 80)
                
            }
        }
        HStack (spacing: 100){
            HStack(spacing: 30) {
                NetworkInterfaceView(netInterfaceType: .cellular, isAvailable: true, linkQualityColor: .green)
                    .frame(height: 80)
                
                NetworkInterfaceView(netInterfaceType: .cellular, isAvailable: false, linkQualityColor: .secondary)
                    .frame(height: 80)
                
            }
            HStack(spacing: 30) {
                NetworkInterfaceView(netInterfaceType: .other, isAvailable: true, linkQualityColor: .green)
                    .frame(height: 80)
                
                NetworkInterfaceView(netInterfaceType: .other, isAvailable: false, linkQualityColor: .secondary)
                    .frame(height: 80)
            }
        }
    }
    .environmentObject(Settings())
    .padding()
}
