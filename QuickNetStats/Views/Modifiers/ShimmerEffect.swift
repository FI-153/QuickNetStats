//
//  VerticallShimmerEffect.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-24.
//

import SwiftUI

struct ShimmerEffect: ViewModifier {
    @State private var startAnimation = false
    var direction: ShimmeringDirections
    var offset: CGFloat = 100
    var duration: CGFloat = 2.5
    
    enum ShimmeringDirections {
        case vertical, horizontal
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    let height = geometry.size.height
                    let width = geometry.size.width
                    
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .clear,
                                    .white.opacity(0.7),
                                    .clear
                                ]),
                                startPoint: direction==ShimmeringDirections.vertical ? .bottom : .leading,
                                endPoint: direction==ShimmeringDirections.vertical ? .top : .trailing
                            )
                        )
                        .frame(width: direction==ShimmeringDirections.vertical ? width*1.2 : height*1.2)
                        .offset(x: direction == .vertical ? 0 : (startAnimation ? 100 : width - offset),
                                y: direction == .vertical ? (startAnimation ? height - offset : 100) : 0
                        )
                }
                    .mask(content)
            )
            .onAppear {
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: false)
                ) {
                    startAnimation.toggle()
                }
            }
    }
}
