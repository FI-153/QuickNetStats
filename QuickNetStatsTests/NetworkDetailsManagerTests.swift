//
//  NetworkDetailsManagerTests.swift
//  QuickNetStatsTests
//

import Testing
import Foundation
import Combine
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

    @Test("getAddresses populates the SSID from the Wi-Fi reader")
    func ssidFetched() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let manager = NetworkDetailsManager(
            session: mockSession(),
            wifiReader: MockWifiReader(result: nil, currentSSID: "HomeNet")
        )
        await manager.getAddresses()

        #expect(manager.ssid == "HomeNet")
    }

    @Test("observeConnectionChanges refetches addresses on a published change")
    func observeRefetchesAddresses() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("93.45.10.2".utf8))
        }
        let manager = NetworkDetailsManager(session: mockSession())

        let subject = PassthroughSubject<NetworkStats, Never>()
        manager.observeConnectionChanges(subject.eraseToAnyPublisher())
        subject.send(.mockGoodEthConnection)

        let populated = await eventually { manager.publicIP == "93.45.10.2" }
        #expect(populated)
    }

    /// Polls `condition` until it is true or the timeout elapses, yielding the
    /// main actor between checks so the observed refetch can complete.
    @discardableResult
    private func eventually(
        timeout: Duration = .seconds(3),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
