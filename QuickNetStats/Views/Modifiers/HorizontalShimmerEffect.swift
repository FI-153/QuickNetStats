//
//  ShimmerEffects.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-24.
//

import SwiftUI

struct HorizontalShimmerEffect: ViewModifier {
    @State private var startAnimation = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    let width = geometry.size.width
                    
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .clear,
                                    .white.opacity(0.5),
                                    .clear
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 100)
                        .offset(x: startAnimation ? width + 100 : -100)
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
