//
//  LinkQualityView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-09.
//

import SwiftUI
import Network

struct LinkQualityView: View {
    
    let linkQuality:LinkQuality
    let linkQualityColor:Color
    
    var linkQualityNumber:Int {
        switch linkQuality {
        case .minimal:
            return 1
        case .moderate:
            return 2
        case .good:
            return 3
        default:
            return 0
        }
    }
        
    let circleDim:CGFloat = 25
    
    var body: some View {
        VStack(spacing: 5){
            
            ZStack(alignment: .leading) {
                HStack{
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .frame(width: circleDim, height: circleDim)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack{
                    ForEach(0..<linkQualityNumber, id: \.self) { _ in
                        Circle()
                            .frame(width: circleDim, height: circleDim)
                            .foregroundStyle(linkQualityColor)
                    }
                }
            }
            .padding(.bottom, 5)
            
            Text("Link Quality")
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Group {
                if linkQuality != .unknown {
                    Text(linkQuality.rawValue.capitalized)
                } else {
                    Text("Computing...")
                        .foregroundStyle(linkQualityColor)
                        .modifier(HorizontalShimmerEffect())
                }
            }
            .foregroundStyle(linkQualityColor)
            
        }
        .frame(width: 80, height: 80)
    }
}

#Preview {
    
    HStack(spacing: 40) {
        LinkQualityView(linkQuality: .good, linkQualityColor: .green)
        LinkQualityView(linkQuality: .moderate, linkQualityColor: .orange)
        LinkQualityView(linkQuality: .minimal, linkQualityColor: .red)
        LinkQualityView(linkQuality: .unknown, linkQualityColor: .secondary)
        
        LinkQualityView(linkQuality: .moderate, linkQualityColor: .primary)

    }
    .padding()
}
