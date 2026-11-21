import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var notifications: NotificationAppDelegate
    @State private var requestFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                permissionRow
                notificationExample
            }
            .frame(maxWidth: 390, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(RuuutoPalette.ink)
        .background(RuuutoPalette.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("通知設定")
                    .font(RuuutoType.rounded(.title3))
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .task { await notifications.refreshAuthorization() }
        .alert("通知設定を変更できませんでした", isPresented: $requestFailed) {
            Button("閉じる", role: .cancel) {}
        }
    }

    private var permissionRow: some View {
        VStack(spacing: 0) {
            rule
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    permissionDescription
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    permissionAction
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    permissionDescription
                    permissionAction
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            rule
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(RuuutoPalette.line)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var permissionDescription: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell")
                .font(.title3)
                .foregroundStyle(RuuutoPalette.soft)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("お題の更新")
                    .font(RuuutoType.rounded(.body))
                permissionStatus
                    .font(RuuutoType.body(.footnote))
                    .foregroundStyle(RuuutoPalette.sub)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var permissionStatus: some View {
        switch notifications.authorizationStatus {
        case .none:
            ProgressView("確認中")
        case .notDetermined, .denied:
            Text("オフ")
        case .provisional:
            Text("仮許可")
        case .authorized, .ephemeral:
            Text("オン")
        @unknown default:
            Text("設定を確認してください")
        }
    }

    @ViewBuilder
    private var permissionAction: some View {
        switch notifications.authorizationStatus {
        case .none:
            EmptyView()
        case .notDetermined, .provisional:
            Button {
                Task {
                    do {
                        try await notifications.requestPermission()
                    } catch {
                        requestFailed = true
                    }
                }
            } label: {
                Text("通知を許可")
                    .font(RuuutoType.rounded(.footnote))
                    .foregroundStyle(notifications.isRequestingPermission ? RuuutoPalette.sub : RuuutoPalette.soft)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(notifications.isRequestingPermission)
        case .denied, .authorized, .ephemeral:
            openSettingsButton
        @unknown default:
            openSettingsButton
        }
    }

    private var openSettingsButton: some View {
        Button(action: notifications.openNotificationSettings) {
            Text("iPhoneの通知設定を開く")
                .font(RuuutoType.rounded(.footnote))
                .foregroundStyle(RuuutoPalette.soft)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var notificationExample: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("通知例")
                .font(RuuutoType.rounded(.caption))
                .foregroundStyle(RuuutoPalette.sub)
            HStack(spacing: 11) {
                Rectangle()
                    .fill(RuuutoPalette.accent)
                    .frame(width: 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("お題が変わりました")
                        .font(RuuutoType.rounded(.body))
                    Text("えーえす班 · 窓の外")
                        .font(RuuutoType.body(.footnote))
                        .foregroundStyle(RuuutoPalette.sub)
                }
                .padding(.vertical, 3)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
