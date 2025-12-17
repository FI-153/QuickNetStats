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
class UpdateManager:ObservableObject {
    @Published var isUpdateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    
    private let owner = "FI-153"
    private let repo = "QuickNetStats"
    private let cooldownTime = 2.0
    
    private var lastCheck:Date = Date.distantPast
    
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    
    private init() {}
    
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
        
        do {
            self.isLoading = true
            self.errorMessage = nil
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            
            let remoteVersion = release.tagName.replacingOccurrences(of: "[vV]", with: "", options:.regularExpression)
            self.latestVersion = remoteVersion
            self.isUpdateAvailable = isVersion(remoteVersion, newerThan: currentVersion)
            
            
        } catch {
            print("Update check failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
        
        self.lastCheck = Date()
        self.isLoading = false
    }
    
    /// Simple semantic version comparison
    /// - Returns True if the current version is not the latest one
    private func isVersion(_ remote: String, newerThan local: String) -> Bool {
        return remote.compare(local, options: .numeric) == .orderedDescending
    }
}

import Playgrounds
#Playground {
    var um = UpdateManager.shared
    let currentVersion = um.getCurrentVersion()
//    await um.checkForUpdates()
//    um.latestVersion
//    um.isUpdateAvailable
}
