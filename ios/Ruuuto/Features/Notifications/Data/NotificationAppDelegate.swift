import Combine
import Foundation
import UIKit
import UserNotifications

enum APNsRegistration: Equatable, Sendable {
    case idle
    case registering
    case registered(Data)
    case failed(domain: String, code: Int)
}

struct RemoteNotificationTap: Identifiable, Equatable, Sendable {
    let id = UUID()
    let customPayload: Data
}

@MainActor
final class NotificationAppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus?
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var registration: APNsRegistration = .idle
    @Published private(set) var pendingTap: RemoteNotificationTap?

    private let notificationCenter = UNUserNotificationCenter.current()
    private var settingsReadID = UUID()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        notificationCenter.delegate = self
        Task { await refreshAuthorization() }
        return true
    }

    // Call on activation to pick up changes made in the system settings.
    func refreshAuthorization() async {
        guard !isRequestingPermission else { return }

        let readID = UUID()
        settingsReadID = readID
        let settings = await notificationCenter.notificationSettings()
        guard settingsReadID == readID else { return }

        updateAuthorization(settings.authorizationStatus)
    }

    // Call in response to the user's explicit choice to enable notifications.
    func requestPermission() async throws {
        guard !isRequestingPermission else { return }

        isRequestingPermission = true
        settingsReadID = UUID()
        defer { isRequestingPermission = false }

        let status = await notificationCenter.notificationSettings().authorizationStatus
        if status == .notDetermined || status == .provisional {
            _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        }
        let settings = await notificationCenter.notificationSettings()
        updateAuthorization(settings.authorizationStatus)
    }

    func openNotificationSettings() {
        guard let settingsURL = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    // Call after authenticated membership and navigation handling have completed.
    func acknowledgeTap(id: RemoteNotificationTap.ID) {
        guard pendingTap?.id == id else { return }
        pendingTap = nil
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard allowsDelivery else { return }
        registration = .registered(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        guard allowsDelivery else { return }
        let error = error as NSError
        registration = .failed(domain: error.domain, code: error.code)
    }

    private var allowsDelivery: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            true
        default:
            false
        }
    }

    private func updateAuthorization(_ status: UNAuthorizationStatus) {
        authorizationStatus = status
        guard allowsDelivery else {
            registration = .idle
            return
        }

        switch registration {
        case .idle, .failed:
            registration = .registering
            UIApplication.shared.registerForRemoteNotifications()
        case .registering, .registered:
            break
        }
    }
}

extension NotificationAppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.trigger is UNPushNotificationTrigger else { return [] }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              response.notification.request.trigger is UNPushNotificationTrigger else { return }

        let customPayload = response.notification.request.content.userInfo.filter { $0.key != AnyHashable("aps") }
        guard JSONSerialization.isValidJSONObject(customPayload),
              let data = try? JSONSerialization.data(withJSONObject: customPayload) else { return }

        let tap = RemoteNotificationTap(customPayload: data)
        await MainActor.run { pendingTap = tap }
    }
}
