//
//  UpdateManagerTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

@Suite("UpdateManager", .serialized)
struct UpdateManagerTests {

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        let token = UUID().uuidString
        config.httpAdditionalHeaders = [MockURLProtocol.tokenHeader: token]
        config.protocolClasses = [MockURLProtocol.self]
        // Snapshot the handler set by the test body into an isolated, token-keyed
        // slot so parallel suites don't clobber each other's global handler.
        MockURLProtocol.handlers[token] = MockURLProtocol.requestHandler
        return URLSession(configuration: config)
    }

    // MARK: - Version tag cleaning

    @Test(
        "cleanVersion strips tag prefixes",
        arguments: [
            ("V.2.3.0", "2.3.0"),
            ("v2.3.0", "2.3.0"),
            ("V2.3.0", "2.3.0"),
            ("2.3.0", "2.3.0"),
            ("V.2.2.0-Beta-1", "2.2.0-Beta-1"),
        ]
    )
    func cleanVersionStripsPrefixes(tag: String, expected: String) {
        #expect(UpdateManager.cleanVersion(fromTag: tag) == expected)
    }

    // MARK: - Version comparison

    @Test("isVersion detects a newer remote version")
    func newerRemoteDetected() {
        let manager = UpdateManager(session: mockSession())
        #expect(manager.isVersion("2.3.0", newerThan: "2.2.0"))
        #expect(!manager.isVersion("2.2.0", newerThan: "2.2.0"))
        #expect(!manager.isVersion("2.1.9", newerThan: "2.2.0"))
    }

    // MARK: - checkForUpdates

    @Test("A newer release tag flags an update")
    func updateAvailableFromRelease() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let body = #"{"tag_name": "V.99.0.0", "html_url": "https://example.com"}"#
            return (response, Data(body.utf8))
        }

        let manager = UpdateManager(session: mockSession())
        await manager.checkForUpdates()

        #expect(manager.isUpdateAvailable)
        #expect(manager.latestVersion == "99.0.0")
        #expect(manager.errorMessage == nil)
    }

    @Test("A non-2xx response surfaces an error, not 'up to date'")
    func httpErrorSurfaced() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 403,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let manager = UpdateManager(session: mockSession())
        await manager.checkForUpdates()

        #expect(manager.errorMessage != nil)
        #expect(!manager.isUpdateAvailable)
        #expect(!manager.isLoading)
    }
}
