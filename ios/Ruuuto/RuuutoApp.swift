import SwiftUI

@main
struct RuuutoApp: App {
    @UIApplicationDelegateAdaptor private var notifications: NotificationAppDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AuthenticationView(notifications: notifications)
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        Task { await notifications.refreshAuthorization() }
                    }
                }
        }
    }
}
