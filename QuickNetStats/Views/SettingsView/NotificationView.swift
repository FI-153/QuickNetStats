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
            
            Section {
                
                ToggleView(title: "Notify When the Interface Changes", variable: settings.$notifyInterfaceChanges)
                
                PickerView(
                    title: "Notify When the Internet",
                    selection: $settings.notifyInternetBehavior
                ) {
                    Text("Connects").tag(InternetNotificationBehavior.connects)
                    Text("Disconnects")
                        .tag(InternetNotificationBehavior.disconnects)
                    Text("Changes").tag(InternetNotificationBehavior.changes)
                }
                
                PickerView(
                    title: "Notify When Link Quality",
                    selection: $settings.notifyQualityBehavior
                ) {
                    Text("Improves")
                        .tag(LinkQualityNotificationBehavior.improves)
                    Text("Worsens")
                        .tag(LinkQualityNotificationBehavior.worsens)
                    Text("Changes").tag(LinkQualityNotificationBehavior.changes)
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
