//
//  SettingsViewModelTests.swift
//  QuickNetStatsTests
//
//  Tests for SettingsViewModel.SettingsPage: titles, icons, colors.
//

import Testing
import SwiftUI
@testable import QuickNetStats

@Suite("SettingsViewModel.SettingsPage")
struct SettingsViewModelTests {

    // MARK: - Titles

    @Test(
        "Each page has the correct display title",
        arguments: [
            (SettingsViewModel.SettingsPage.menubar, "Menu Bar"),
            (SettingsViewModel.SettingsPage.visuals, "Visuals"),
            (SettingsViewModel.SettingsPage.notifications, "Notifications"),
            (SettingsViewModel.SettingsPage.about, "About"),
        ]
    )
    func pageTitles(page: SettingsViewModel.SettingsPage, expected: String) {
        #expect(page.title == expected)
    }

    // MARK: - Icons

    @Test(
        "Each page has the correct SF Symbol icon",
        arguments: [
            (SettingsViewModel.SettingsPage.menubar, "menubar.rectangle"),
            (SettingsViewModel.SettingsPage.visuals, "accessibility"),
            (SettingsViewModel.SettingsPage.notifications, "bell.badge"),
            (SettingsViewModel.SettingsPage.about, "info.circle"),
        ]
    )
    func pageIcons(page: SettingsViewModel.SettingsPage, expected: String) {
        #expect(page.icon == expected)
    }

    // MARK: - Colors

    @Test(
        "Each page has the correct color",
        arguments: [
            (SettingsViewModel.SettingsPage.menubar, Color.red),
            (SettingsViewModel.SettingsPage.visuals, Color.blue),
            (SettingsViewModel.SettingsPage.notifications, Color.green),
            (SettingsViewModel.SettingsPage.about, Color.gray),
        ]
    )
    func pageColors(page: SettingsViewModel.SettingsPage, expected: Color) {
        #expect(page.color == expected)
    }

    // MARK: - CaseIterable & Identifiable

    @Test("allCases contains exactly 4 pages")
    func allCasesCount() {
        #expect(SettingsViewModel.SettingsPage.allCases.count == 4)
    }

    @Test("id matches rawValue for each page")
    func identifiableConformance() {
        for page in SettingsViewModel.SettingsPage.allCases {
            #expect(page.id == page.rawValue)
        }
    }
}
