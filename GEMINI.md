# QuickNetStats

QuickNetStats is a macOS Menu Bar application that provides real-time network statistics, including connection type, link quality, and IPv4 addresses. It is built using Swift and SwiftUI.

## Project Overview

- **Platform:** macOS 13.0 (Ventura) and later.
- **Language:** Swift 5.9+.
- **Frameworks:** SwiftUI, Network (`NWPathMonitor`), SystemConfiguration.
- **Architecture:** MVVM-like pattern with `Manager` classes handling business logic and `View` structs for UI.

## Directory Structure

*   `QuickNetStats/`
    *   `QuickNetStatsApp.swift`: The main entry point of the application, defining the `MenuBarExtra`.
    *   `Managers/`: Contains the core logic for network monitoring.
        *   `NetworkStatsManager.swift`: Monitors network changes (WiFi, Ethernet, etc.) using `NWPathMonitor`.
        *   `NetworkDetailsManager.swift`: Fetches public (via `api.ipify.org`) and private IP addresses.
        *   `NotificationsManager.swift`: Handles local notifications.
        *   `StartAtLoginManager.swift`: Manages the "Launch at Login" functionality.
        *   `UpdateManager.swift`: Checks for app updates via GitHub Releases.
    *   `Models/`: Data models used throughout the app.
        *   `NetworkStats.swift`: Represents the current network state.
        *   `Settings.swift`: Manages user preferences.
    *   `Views/`: SwiftUI views.
        *   `ContentView.swift`: The main view displayed when clicking the menu bar icon.
        *   `Camponents/`: Reusable UI components (`AddressView`, `LinkQualityView`, etc.).
        *   `Modifiers/`: View modifiers (e.g., `ShimmerEffect`).
        *   `NetStatsView/`:
            *   `NetStatsView.swift`: Display of network statistics.
            *   `NetStatsViewModel.swift`: ViewModel for network stats logic.
        *   `SettingsView/`:
            *   `SettingsView.swift`: The settings window UI.
            *   `SettingsViewModel.swift`: ViewModel for settings logic.
            *   `AboutView.swift`, `MenuBarView.swift`, `VisualsView.swift`: Settings sub-pages.
    *   `quicknetstats.icon/`: Source files for the application icon.
    *   `Assets/`: Static assets (images, icons).

## Building and Running

This is a standard Xcode project.

1.  **Open the project:**
    ```bash
    open QuickNetStats.xcodeproj
    ```
2.  **Build and Run:**
    *   Select the `QuickNetStats` scheme.
    *   Press `Cmd + R` to build and run the app.
    *   The app will appear in the macOS Menu Bar.

## Key Features & Implementation Details

*   **Network Monitoring:** Uses `NWPathMonitor` to detect changes in network interfaces (WiFi, Ethernet, Hotspot).
*   **Link Quality:** The `NetworkStatsManager` includes a check for `macOS 26` (likely a placeholder or future API `path.linkQuality`) for detailed link quality metrics.
*   **IP Addresses:**
    *   **Public IP:** Fetched asynchronously from `https://api.ipify.org`.
    *   **Private IP:** Retrieved by iterating through network interfaces (`getifaddrs`) to find the first valid IPv4 address on `en` interfaces.

## Development Conventions

*   **Swift Style:** Follows standard Swift API Design Guidelines.
*   **Concurrency:** Uses Swift Concurrency (`async`/`await`) for network operations.
*   **UI:** Built entirely with SwiftUI.
*   **Playgrounds:** Some files contain `#Playground` blocks for testing logic in isolation.
*   **Contributing:** Please refer to `CONTRIBUTING.md` for detailed guidelines on pull requests, code style, and testing.

## Dependencies

*   **External:** None explicitly managed via package manager (based on file listing), but `QuickNetStats.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration` suggests Swift Package Manager might be used. Check `Project Settings` in Xcode for specifics.
