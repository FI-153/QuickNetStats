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

    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    /// Guards `_requestHandler` and `_handlers`. Reads happen on the URL loading system's
    /// background threads inside `startLoading()`; writes happen on the main actor from
    /// each suite's `mockSession()` helper. Swift Testing runs suites concurrently, so a
    /// write from one suite can overlap a read from another in-flight suite — without this
    /// lock that's a concurrent Dictionary read/write, which is undefined behavior.
    nonisolated(unsafe) private static let lock = NSLock()

    nonisolated(unsafe) private static var _requestHandler: Handler?

    /// Per-session handlers keyed by a token carried in the request headers.
    /// Lets suites that mock different hosts run in parallel without clobbering
    /// each other's global `requestHandler` (Swift Testing runs suites concurrently).
    nonisolated(unsafe) private static var _handlers: [String: Handler] = [:]

    /// The fallback handler used when a request carries no per-token entry in `handlers`.
    /// All reads and writes go through `lock`.
    nonisolated static var requestHandler: Handler? {
        get { lock.withLock { _requestHandler } }
        set { lock.withLock { _requestHandler = newValue } }
    }

    /// Token-keyed handlers, see `_handlers`. All reads and writes go through `lock`.
    nonisolated static var handlers: [String: Handler] {
        get { lock.withLock { _handlers } }
        set { lock.withLock { _handlers = newValue } }
    }

    /// The header used to route a request to its owning session's handler.
    static let tokenHeader = "X-Mock-Token"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let scopedHandler = request.value(forHTTPHeaderField: Self.tokenHeader)
            .flatMap { Self.handlers[$0] }

        guard let handler = scopedHandler ?? Self.requestHandler else {
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
        let token = UUID().uuidString
        config.httpAdditionalHeaders = [MockURLProtocol.tokenHeader: token]
        config.protocolClasses = [MockURLProtocol.self]
        // Snapshot the handler set by the test body into an isolated, token-keyed
        // slot so parallel suites don't clobber each other's global handler.
        MockURLProtocol.handlers[token] = MockURLProtocol.requestHandler
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
