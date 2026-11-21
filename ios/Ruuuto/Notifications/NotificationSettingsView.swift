import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var notifications: NotificationAppDelegate
    @State private var requestFailed = false

    var body: some View {
        Form {
            Section("お題の更新") {
                switch notifications.authorizationStatus {
                case .none:
                    ProgressView("通知設定を確認中")
                case .notDetermined, .provisional:
                    Text("お題が変わったときに通知を受け取れます。")
                    Button("通知を許可") {
                        Task {
                            do {
                                try await notifications.requestPermission()
                            } catch {
                                requestFailed = true
                            }
                        }
                    }
                    .disabled(notifications.isRequestingPermission)
                case .denied:
                    Text("通知はオフです。iPhoneの設定から変更できます。")
                    Button("iPhoneの通知設定を開く", action: notifications.openNotificationSettings)
                case .authorized, .ephemeral:
                    Text("通知はオンです。")
                    Button("iPhoneの通知設定を開く", action: notifications.openNotificationSettings)
                @unknown default:
                    Button("iPhoneの通知設定を開く", action: notifications.openNotificationSettings)
                }
            }
        }
        .navigationTitle("通知")
        .task { await notifications.refreshAuthorization() }
        .alert("通知設定を変更できませんでした", isPresented: $requestFailed) {
            Button("閉じる", role: .cancel) {}
        }
    }
}
