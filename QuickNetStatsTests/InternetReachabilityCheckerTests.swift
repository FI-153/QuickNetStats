//
//  InternetReachabilityCheckerTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
@testable import QuickNetStats

// MARK: - Mock URL Protocol

/// A mock URL protocol that intercepts all requests and returns configurable responses.
/// Uses a static `requestHandler` closure to determine behavior per request.
class MockURLProtocol: URLProtocol {

    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Tests

@Suite("InternetReachabilityChecker", .serialized)
struct InternetReachabilityCheckerTests {

    /// Creates a `URLSession` that routes all requests through `MockURLProtocol`.
    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("Returns true when first endpoint succeeds")
    func firstEndpointSucceeds() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let checker = InternetReachabilityChecker(session: mockSession())
        let result = await checker.checkReachability()
        #expect(result == true)
    }

    @Test("Returns false when all endpoints fail with network error")
    func allEndpointsFailWithError() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let checker = InternetReachabilityChecker(session: mockSession())
        let result = await checker.checkReachability()
        #expect(result == false)
    }

    @Test("Returns false when all endpoints return non-2xx status")
    func allEndpointsReturnServerError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 503,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let checker = InternetReachabilityChecker(session: mockSession())
        let result = await checker.checkReachability()
        #expect(result == false)
    }

    @Test("Falls back to second endpoint when first fails")
    func fallsBackToSecondEndpoint() async {
        MockURLProtocol.requestHandler = { request in
            if request.url!.absoluteString.contains("captive.apple.com") {
                throw URLError(.timedOut)
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let checker = InternetReachabilityChecker(session: mockSession())
        let result = await checker.checkReachability()
        #expect(result == true)
    }

    @Test("Falls back to third endpoint when first two fail")
    func fallsBackToThirdEndpoint() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            if url.contains("captive.apple.com") || url.contains("connectivitycheck") {
                throw URLError(.timedOut)
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let checker = InternetReachabilityChecker(session: mockSession())
        let result = await checker.checkReachability()
        #expect(result == true)
    }
}
