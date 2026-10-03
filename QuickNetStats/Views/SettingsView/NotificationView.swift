import SwiftUI

struct NotificationView: View {
    @ObservedObject var settings: Settings
    @ObservedObject private var notificationsManager = NotificationsManager.shared

    var body: some View {
        Form {

            if !notificationsManager.areNotificationsEnabled {
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
                    notificationsManager.requestNotificationPermission()
                }
                notificationsManager.checkNotificationStatus()
            }
            
            Section("Network Interface") {
                ToggleView(title: "Notify on Changes", variable: settings.$notifyInterfaceChanges)
            }

            Section("Internet") {
                ToggleView(title: "Internet Status", variable: settings.$notifyInternetEnabled.animation())

                if settings.notifyInternetEnabled {
                    PickerView(
                        title: "When",
                        selection: $settings.notifyInternetBehavior
                    ) {
                        Text("Connects").tag(InternetNotificationBehavior.connects)
                        Text("Disconnects")
                            .tag(InternetNotificationBehavior.disconnects)
                        Text("Changes").tag(InternetNotificationBehavior.changes)
                    }
                }
            }

            Section("Connection Quality") {
                ToggleView(title: "Link Quality", variable: settings.$notifyQualityEnabled.animation())

                if settings.notifyQualityEnabled {
                    PickerView(
                        title: "When",
                        selection: $settings.notifyQualityBehavior
                    ) {
                        Text("Improves")
                            .tag(LinkQualityNotificationBehavior.improves)
                        Text("Worsens")
                            .tag(LinkQualityNotificationBehavior.worsens)
                        Text("Changes").tag(LinkQualityNotificationBehavior.changes)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            notificationsManager.checkNotificationStatus()
        }
    }
}

#Preview {
    NotificationView(settings: Settings())
}
