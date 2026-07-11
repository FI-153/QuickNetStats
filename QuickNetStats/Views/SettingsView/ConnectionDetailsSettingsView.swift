//
//  ConnectionDetailsSettingsView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2026-07-06.
//

import SwiftUI

/// Settings page letting the user pick the display unit (bits vs bytes per second)
/// for each rate-bearing section of the Connection Details dropdown. Defaults equal
/// each section's native unit, so the dropdown looks identical until changed.
struct ConnectionDetailsSettingsView: View {

    @ObservedObject var settings: Settings

    /// Page-local owner of the Location Services authorization state, driving the
    /// opt-in network-names toggle's one-time prompt.
    @StateObject private var locationPermission = LocationPermissionManager()

    /// Shown right after the user grants the Location Services prompt: CoreWLAN
    /// only picks up the new permission at launch, so SSID/BSSID stay empty until
    /// the app restarts.
    @State private var showRestartAlert = false

    var body: some View {
        Form {
            Section {
                unitPicker(
                    title: "Interface",
                    description: "Link speed",
                    selection: $settings.interfaceRateUnit
                )

                unitPicker(
                    title: "Wi-Fi",
                    description: "Tx rate",
                    selection: $settings.wifiRateUnit
                )

                unitPicker(
                    title: "Live",
                    description: "Download and Upload",
                    selection: $settings.liveRateUnit
                )
            } header: {
                Text("Rate Units")
            }
            
            Section {
                ToggleView(
                    title: "Start live monitoring immediately",
                    variable: $settings.startLiveMonitoringOnOpen,
                    description: "Start monitoring of Live Stats when 'Connection Details' opens"
                )
            } header: {
                Text("Live Stats")
            }

            Section {
                ToggleView(
                    title: "Show network name (SSID) & BSSID",
                    variable: showNetworkNamesBinding,
                    description: "Displays the Wi-Fi name in the main window and the BSSID in "
                        + "'Connection Details'. macOS requires Location Services permission for "
                        + "these; your location is never collected or stored."
                )

                if locationPermission.state == .denied {
                    HStack {
                        Text("Location access is denied. Allow QuickNetStats under Privacy & Security → Location Services.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Open Settings") { openLocationSettings() }
                    }
                }
            } header: {
                Text("Network Names")
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Restart QuickNetStats", isPresented: $showRestartAlert) {
            Button("Quit Now") { NSApp.terminate(nil) }
            Button("Later", role: .cancel) { }
        } message: {
            Text("macOS applies the Location Services permission when the app starts. "
                + "Quit and reopen QuickNetStats to see the network name and BSSID.")
        }
    }

    /// Bridges the toggle to `Settings.showNetworkNames`, injecting the one-time
    /// Location Services prompt: while undetermined the toggle stays off and the
    /// system prompt decides; once authorized it flips freely without re-prompting.
    private var showNetworkNamesBinding: Binding<Bool> {
        Binding(
            get: { settings.showNetworkNames },
            set: { isOn in
                guard isOn else {
                    settings.showNetworkNames = false
                    return
                }
                
                switch locationPermission.state {
                case .authorized:
                    settings.showNetworkNames = true
                case .notDetermined:
                    locationPermission.requestAuthorization {
                        settings.showNetworkNames = true
                        showRestartAlert = true
                    }
                case .denied:
                    break   // stays off; the caption below offers the recovery path
                }
            }
        )
    }

    /// Opens System Settings on the Location Services privacy pane (mirrors
    /// `ContentView.openNetworkSettings()`).
    private func openLocationSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// One labeled picker offering every `RateUnit`, tagged so the binding round-trips.
    private func unitPicker(
        title: String,
        description: String,
        selection: Binding<RateUnit>
    ) -> some View {
        PickerView(title: title, selection: selection, description: description) {
            ForEach(RateUnit.allCases) { unit in
                Text(unit.displayName).tag(unit)
            }
        }
    }
}

#Preview {
    ConnectionDetailsSettingsView(settings: Settings())
}
