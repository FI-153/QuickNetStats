//
//  UpdateManager.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-16.
//

import SwiftUI
import Combine

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String
    
    enum CodingKeys: String, CodingKey { 
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}

@MainActor
class UpdateManager: ObservableObject {
    @Published var isUpdateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    
    private let owner = "FI-153"
    private let repo = "QuickNetStats"
    private let cooldownTime = 2.0
    
    private var lastCheck: Date = Date.distantPast
    
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// The URLSession used for network requests (injectable for testing).
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Shared instance of the singleton UpdateManager class
    static let shared = UpdateManager()
    
    /// Current app version
    /// - Returns The current app vesion as a string or 0.0.0 in case of error
    func getCurrentVersion() -> String {
        return currentVersion
    }
    
    /// Determine if the managet can do a new request (i.e. if 2 minutes have passed since the last successful fetch
    func isCoolingDown() -> Bool {
        return Date() < lastCheck.addingTimeInterval(60*cooldownTime)
    }
    
    /// Call the GitHub public API to fetch the latest release of the app, then retrieve the version number, update
    /// it and check if there is a newer version than the one installed.
    ///
    /// Updates are limited to once every 2 minutes. Multiple requests within 2 minutes will be discarded
    func checkForUpdates() async {
    
        // Allow to check for updates only once every 2 minutes to prevent suprassing GitHub's limit
        if self.isCoolingDown() {
            print("Cannot update more than once every \(self.cooldownTime) minute\(self.cooldownTime > 1 ? "s" : "")")
            return
        }
        
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("QuickNetStatsApp", forHTTPHeaderField: "User-Agent")

        self.isLoading = true
        self.errorMessage = nil
        defer {
            self.lastCheck = Date()
            self.isLoading = false
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                self.errorMessage = "GitHub responded with an unexpected status code"
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            let remoteVersion = Self.cleanVersion(fromTag: release.tagName)
            self.latestVersion = remoteVersion
            self.isUpdateAvailable = isVersion(remoteVersion, newerThan: currentVersion)

        } catch {
            print("Update check failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }

    /// Strips a leading "v"/"V" and optional dot from a release tag (e.g. "V.2.3.0" -> "2.3.0").
    static func cleanVersion(fromTag tag: String) -> String {
        tag.replacingOccurrences(of: "^[vV]\\.?", with: "", options: .regularExpression)
    }

    /// Pre-release-aware version comparison.
    ///
    /// Each version is split into a numeric base (up to the first "-") and an optional pre-release
    /// suffix, e.g. "3.0.0-Beta-2" -> base "3.0.0", suffix "Beta-2".
    /// - Different bases: a numeric comparison of the bases decides.
    /// - Equal bases: the remote is newer only when the local build is a pre-release and the remote
    ///   is the stable release (the stable release supersedes its own betas). Two pre-releases with
    ///   the same base are treated as equal — GitHub's /releases/latest endpoint never returns a
    ///   pre-release, so that case is unreachable in practice.
    /// - Returns True if the remote version is newer than the local one
    func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let remoteBase = String(remote.prefix(while: { $0 != "-" }))
        let localBase = String(local.prefix(while: { $0 != "-" }))

        guard remoteBase == localBase else {
            return remoteBase.compare(localBase, options: .numeric) == .orderedDescending
        }

        // Equal bases: a stable remote (no suffix) supersedes a pre-release local.
        return remote == remoteBase && local != localBase
    }

    /// Whether a version string denotes a beta build (contains "beta", case-insensitive).
    static func isBetaVersion(_ version: String) -> Bool {
        version.range(of: "beta", options: .caseInsensitive) != nil
    }

    /// Whether the currently running build is a beta.
    var isBetaBuild: Bool {
        Self.isBetaVersion(currentVersion)
    }
}
