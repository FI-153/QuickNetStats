//
//  ClipboardTests.swift
//  QuickNetStatsTests
//
//  Tests for Clipboard: copying values to an isolated, uniquely named pasteboard.
//

import Testing
import AppKit
@testable import QuickNetStats

@Suite("Clipboard")
@MainActor
struct ClipboardTests {

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: .init("qns-test-\(UUID().uuidString)"))
    }

    @Test("copy writes a non-empty value and reports success")
    func copiesValue() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        #expect(Clipboard.copy("10.0.0.32", to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "10.0.0.32")
    }

    @Test(
        "copy rejects nil or empty values and leaves the pasteboard untouched",
        arguments: [nil, ""] as [String?]
    )
    func rejectsMissingValue(value: String?) {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("keep", forType: .string)

        #expect(Clipboard.copy(value, to: pasteboard) == false)
        #expect(pasteboard.string(forType: .string) == "keep")
    }
}
