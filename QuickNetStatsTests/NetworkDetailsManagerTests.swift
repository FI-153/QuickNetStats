//
//  NetworkDetailsManagerTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

@Suite("NetworkDetailsManager", .serialized)
struct NetworkDetailsManagerTests {

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

    @Test("A successful ipify response populates publicIP")
    func publicIPFetched() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data("93.45.10.2".utf8))
        }

        let manager = NetworkDetailsManager(session: mockSession())
        await manager.getAddresses()

        #expect(manager.publicIP == "93.45.10.2")
    }

    @Test("A server error leaves publicIP nil")
    func publicIPNilOnServerError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let manager = NetworkDetailsManager(session: mockSession())
        await manager.getAddresses()

        #expect(manager.publicIP == nil)
    }
}
