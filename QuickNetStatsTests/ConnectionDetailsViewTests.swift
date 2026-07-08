//
//  ConnectionDetailsViewTests.swift
//  QuickNetStatsTests
//
//  Tests for ConnectionDetailsView: dynamic scroll-height cap derived from the
//  current screen height.
//

import Testing
import SwiftUI
@testable import QuickNetStats

@Suite("ConnectionDetailsView")
@MainActor
struct ConnectionDetailsViewTests {

    // MARK: - Max details height

    @Test(
        "maxDetailsHeight is 3/4 of the screen height, or the 600 fallback when unknown",
        arguments: [
            (CGFloat(1080), CGFloat(810)),
            (CGFloat(2000), CGFloat(1500)),
            (nil, CGFloat(600)),
        ] as [(CGFloat?, CGFloat)]
    )
    func maxDetailsHeightForScreenHeight(screenHeight: CGFloat?, expected: CGFloat) {
        #expect(ConnectionDetailsView.maxDetailsHeight(forScreenHeight: screenHeight) == expected)
    }
}
