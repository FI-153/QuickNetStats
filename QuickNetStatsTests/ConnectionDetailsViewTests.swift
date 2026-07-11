//
//  ConnectionDetailsViewTests.swift
//  QuickNetStatsTests
//
//  Tests for ConnectionDetailsView: dynamic scroll-height cap derived from the
//  current screen height, visible area, and measured popover chrome.
//

import Testing
import SwiftUI
@testable import QuickNetStats

@Suite("ConnectionDetailsView")
@MainActor
struct ConnectionDetailsViewTests {

    // MARK: - Max details height

    @Test(
        "maxDetailsHeight bounds the details cap by screen, visible area, and chrome",
        arguments: [
            // Unknown screen falls back to the fixed 600 cap.
            (nil, nil, nil, CGFloat(600)),
            // Plain 3/4 bound when the visible/chrome measurements are unavailable.
            (CGFloat(956), nil, nil, CGFloat(717)),
            // Large display: the 3/4 bound stays the binding one.
            (CGFloat(1440), CGFloat(1400), CGFloat(300), CGFloat(1080)),
            // 13" MacBook Air: the visible-minus-chrome bound wins so nothing overflows.
            (CGFloat(956), CGFloat(860), CGFloat(300), CGFloat(544)),
            // Absurd chrome can never collapse the details below the floor.
            (CGFloat(956), CGFloat(860), CGFloat(900), CGFloat(100)),
        ] as [(CGFloat?, CGFloat?, CGFloat?, CGFloat)]
    )
    func maxDetailsHeightBounds(
        screenHeight: CGFloat?,
        visibleHeight: CGFloat?,
        chromeHeight: CGFloat?,
        expected: CGFloat
    ) {
        #expect(
            ConnectionDetailsView.maxDetailsHeight(
                screenHeight: screenHeight,
                visibleHeight: visibleHeight,
                chromeHeight: chromeHeight
            ) == expected
        )
    }
}
