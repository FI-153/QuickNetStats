//
//  InternetReachabilityChecker.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-04-11.
//

import Foundation

// MARK: - Protocol

/// Checks whether the device can reach the public internet.
protocol InternetReachabilityChecking {
    /// Returns `true` if at least one public endpoint is reachable.
    func checkReachability() async -> Bool
}

// MARK: - Implementation

/// Tries a sequence of well-known public endpoints to confirm internet reachability.
/// Stops at the first success; returns `false` only if all endpoints fail.
class InternetReachabilityChecker: InternetReachabilityChecking {

    /// The endpoints to try, in order.
    private let endpoints: [URL] = [
        URL(string: "https://captive.apple.com")!,
        URL(string: "https://connectivitycheck.gstatic.com/generate_204")!,
        URL(string: "https://1.1.1.1/cdn-cgi/trace")!
    ]

    /// A dedicated session with short timeouts for reachability checks.
    private let session: URLSession

    /// Creates a checker with the given session (injectable for testing).
    init(session: URLSession = .reachabilitySession) {
        self.session = session
    }

    func checkReachability() async -> Bool {
        for endpoint in endpoints {
            do {
                let (_, response) = try await session.data(from: endpoint)
                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    return true
                }
            } catch {
                // The current endpoint fails -> Check the next
                continue
            }
        }
        
        // All checks fails -> No internet
        return false
    }
}

// MARK: - URLSession Extension

extension URLSession {

    /// A shared session configured with 5-second timeouts for reachability checks.
    static let reachabilitySession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()
}
