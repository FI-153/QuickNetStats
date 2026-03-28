//
//  GitHubReleaseTests.swift
//  QuickNetStatsTests
//
//  Tests for GitHubRelease JSON decoding.
//

import Testing
import Foundation
@testable import QuickNetStats

@Suite("GitHubRelease Decoding")
struct GitHubReleaseTests {

    @Test("Decodes valid JSON with snake_case keys")
    func decodesValidJSON() throws {
        let json = """
        {
            "tag_name": "v2.1.0",
            "html_url": "https://github.com/FI-153/QuickNetStats/releases/tag/v2.1.0"
        }
        """.data(using: .utf8)!

        let release = try #require(try JSONDecoder().decode(GitHubRelease.self, from: json))
        #expect(release.tagName == "v2.1.0")
        #expect(release.htmlUrl == "https://github.com/FI-153/QuickNetStats/releases/tag/v2.1.0")
    }

    @Test("Fails to decode when required fields are missing")
    func failsOnMissingFields() {
        let json = """
        { "tag_name": "v1.0.0" }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GitHubRelease.self, from: json)
        }
    }

    @Test("Decodes beta release tag names")
    func decodeBetaTag() throws {
        let json = """
        {
            "tag_name": "V.2.1.0-Beta-2",
            "html_url": "https://github.com/FI-153/QuickNetStats/releases/tag/V.2.1.0-Beta-2"
        }
        """.data(using: .utf8)!

        let release = try #require(try JSONDecoder().decode(GitHubRelease.self, from: json))
        #expect(release.tagName == "V.2.1.0-Beta-2")
    }
}
