import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var notifications: NotificationAppDelegate
    @State private var requestFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "bell")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(RuuutoPalette.ink)
                    .padding(14)
                    .background(RuuutoPalette.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)

                Text("お題の更新")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(RuuutoPalette.ink)
                    .accessibilityAddTraits(.isHeader)

                permissionContent
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(RuuutoPalette.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(RuuutoPalette.page.ignoresSafeArea())
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .task { await notifications.refreshAuthorization() }
        .alert("通知設定を変更できませんでした", isPresented: $requestFailed) {
            Button("閉じる", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var permissionContent: some View {
        switch notifications.authorizationStatus {
        case .none:
            ProgressView("通知設定を確認中")
                .tint(RuuutoPalette.ink)
                .foregroundStyle(RuuutoPalette.ink)
                .padding(.vertical, 8)
        case .notDetermined, .provisional:
            Text("お題が変わったときに通知を受け取れます。")
                .foregroundStyle(RuuutoPalette.sub)
            notificationButton("通知を許可", icon: "bell.badge") {
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
            permissionStatus("通知はオフです。iPhoneの設定から変更できます。", icon: "bell.slash")
            openSettingsButton
        case .authorized, .ephemeral:
            permissionStatus("通知はオンです。", icon: "checkmark.circle")
            openSettingsButton
        @unknown default:
            openSettingsButton
        }
    }

    private var openSettingsButton: some View {
        notificationButton("iPhoneの通知設定を開く", icon: "gearshape", action: notifications.openNotificationSettings)
    }

    private func permissionStatus(_ title: LocalizedStringKey, icon: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .accessibilityHidden(true)
        }
        .foregroundStyle(RuuutoPalette.ink)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RuuutoPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func notificationButton(
        _ title: LocalizedStringKey,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(.body, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(RuuutoPalette.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.large)
        .tint(RuuutoPalette.accent)
    }
}
