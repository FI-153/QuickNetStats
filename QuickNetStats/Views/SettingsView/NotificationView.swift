import SwiftUI

struct NotificationView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section {
                ToggleView(
                    title: "Send Notifications",
                    variable: settings.$isNotificationActive,
                    description: "Send notifications immediately when stuff happens"
                )
            } header: {
                Text("Notifications Settings")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    NotificationView(settings: Settings())
}
