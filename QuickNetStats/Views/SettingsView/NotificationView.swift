import SwiftUI

struct NotificationView: View {
    @ObservedObject var settings: Settings
    
    init(settings: Settings) {
        self.settings = settings
        NotificationsManager.shared.checkNotificationStatus()
    }

    var body: some View {
        Form {
            
            if !NotificationsManager.shared.areNotificationsEnabled {
                Section {
                    Text("Notifications are disabled by the user")
                }
            }
            
            Section {
                ToggleView(
                    title: "Send Notifications",
                    variable: settings.$isNotificationActive,
                    description: "Send notifications immediately when stuff happens"
                )
                .onChange(of: settings.isNotificationActive) { newValue in
                    if newValue == true {
                        NotificationsManager.shared.requestNotificationPermission()
                    }
                    NotificationsManager.shared.checkNotificationStatus()
                }

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
