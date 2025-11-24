//
//  VerticallShimmerEffect.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-24.
//

import SwiftUI

struct VerticalShimmerEffect: ViewModifier {
    @State private var startAnimation = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    let height = geometry.size.height
                    
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .clear,
                                    .white.opacity(0.5),
                                    .clear
                                ]),
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 100)
                        .offset(y: startAnimation ? height - 200 : 100)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2)
                    .repeatForever(autoreverses: false)
                ) {
                    startAnimation.toggle()
                }
            }
    }
}
