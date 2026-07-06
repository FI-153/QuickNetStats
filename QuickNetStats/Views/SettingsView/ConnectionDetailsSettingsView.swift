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
        }
        .formStyle(.grouped)
        .padding()
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
