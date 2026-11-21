import Combine
import Foundation
import Observation
import UserNotifications

enum NotificationDeviceRegistration: Equatable, Sendable {
    case registered(Data)
    case unregistered
}

struct NotificationDestination: Equatable, Sendable {
    let groupID: UUID
    let boardID: UUID
}

struct NotificationTapEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let destination: NotificationDestination
}

@MainActor
@Observable
final class NotificationSettingsViewModel {
    enum DeviceSyncState: Equatable {
        case idle
        case syncing
        case synchronized
        case failed
    }

    private struct DeviceSyncRequest: Equatable {
        let userID: UUID
        let registration: NotificationDeviceRegistration
    }

    private let notifications: NotificationAppDelegate
    private let decodeDestination: (Data) -> NotificationDestination?
    // Apply the requested state for this installation under this user's authenticated session.
    private let synchronizeDevice: (UUID, NotificationDeviceRegistration) async throws -> Void

    @ObservationIgnored private var notificationsObservation: AnyCancellable?
    @ObservationIgnored private var synchronizationTask: Task<Void, Never>?

    private var signedInUserID: UUID?
    private var suspendedUserID: UUID?
    private var lastSynchronized: DeviceSyncRequest?
    private var observedTapID: UUID?

    private(set) var authorizationStatus: UNAuthorizationStatus?
    private(set) var isRequestingPermission = false
    private(set) var permissionRequestFailed = false
    private(set) var registration: APNsRegistration = .idle
    private(set) var deviceSyncState: DeviceSyncState = .idle
    private(set) var pendingTap: NotificationTapEvent?

    init(
        notifications: NotificationAppDelegate,
        decodeDestination: @escaping (Data) -> NotificationDestination?,
        synchronizeDevice: @escaping (UUID, NotificationDeviceRegistration) async throws -> Void
    ) {
        self.notifications = notifications
        self.decodeDestination = decodeDestination
        self.synchronizeDevice = synchronizeDevice

        notificationsObservation = notifications.$authorizationStatus
            .combineLatest(notifications.$isRequestingPermission, notifications.$registration, notifications.$pendingTap)
            .sink { [weak self] status, requesting, registration, tap in
                self?.update(status: status, requesting: requesting, registration: registration, tap: tap)
            }
    }

    func refreshAuthorization() async {
        await notifications.refreshAuthorization()
    }

    func requestPermission() async {
        guard !isRequestingPermission else { return }
        permissionRequestFailed = false
        do {
            try await notifications.requestPermission()
        } catch {
            permissionRequestFailed = true
        }
    }

    func openSystemSettings() {
        notifications.openNotificationSettings()
    }

    func setSignedInUser(_ userID: UUID?) {
        guard signedInUserID != userID else { return }
        signedInUserID = userID
        suspendedUserID = nil
        lastSynchronized = nil
        deviceSyncState = .idle
        scheduleSynchronization()
    }

    func retryDeviceSynchronization() {
        scheduleSynchronization()
    }

    // The app calls this before invalidating the session used to unregister the installation.
    func unregisterBeforeSignOut() async throws {
        guard let userID = signedInUserID, suspendedUserID == nil else { return }
        suspendedUserID = userID

        await synchronizationTask?.value
        guard signedInUserID == userID, suspendedUserID == userID else { return }

        let removal = DeviceSyncRequest(userID: userID, registration: .unregistered)
        do {
            if lastSynchronized != removal {
                try await synchronizeDevice(userID, .unregistered)
            }
            guard signedInUserID == userID, suspendedUserID == userID else { return }
            lastSynchronized = removal
            deviceSyncState = .synchronized
        } catch {
            if signedInUserID == userID, suspendedUserID == userID {
                suspendedUserID = nil
                deviceSyncState = .failed
            }
            throw error
        }
    }

    func resumeAfterFailedSignOut() {
        suspendedUserID = nil
        scheduleSynchronization()
    }

    // The app validates authentication and membership before routing to this destination.
    func acknowledgeTap(_ event: NotificationTapEvent) {
        notifications.acknowledgeTap(id: event.id)
    }

    private var desiredRegistration: DeviceSyncRequest? {
        guard let userID = signedInUserID, suspendedUserID == nil else { return nil }

        let desired: NotificationDeviceRegistration
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            guard case .registered(let token) = registration else { return nil }
            desired = .registered(token)
        case .notDetermined, .denied:
            desired = .unregistered
        default:
            return nil
        }

        return DeviceSyncRequest(userID: userID, registration: desired)
    }

    private func update(
        status: UNAuthorizationStatus?,
        requesting: Bool,
        registration: APNsRegistration,
        tap: RemoteNotificationTap?
    ) {
        let previous = desiredRegistration
        authorizationStatus = status
        isRequestingPermission = requesting
        self.registration = registration

        if observedTapID != tap?.id {
            observedTapID = tap?.id
            pendingTap = tap.flatMap { incoming in
                decodeDestination(incoming.customPayload).map { destination in
                    NotificationTapEvent(id: incoming.id, destination: destination)
                }
            }
        }

        if previous != desiredRegistration {
            scheduleSynchronization()
        }
    }

    private func scheduleSynchronization() {
        guard synchronizationTask == nil,
              let desiredRegistration, desiredRegistration != lastSynchronized else { return }

        deviceSyncState = .syncing
        synchronizationTask = Task { [weak self] in
            await self?.synchronizeLatestRegistration()
        }
    }

    private func synchronizeLatestRegistration() async {
        defer { synchronizationTask = nil }

        while let request = desiredRegistration, request != lastSynchronized {
            deviceSyncState = .syncing
            do {
                try await synchronizeDevice(request.userID, request.registration)
                if signedInUserID == request.userID {
                    lastSynchronized = request
                }
            } catch {
                if request == desiredRegistration {
                    deviceSyncState = .failed
                    return
                }
            }
        }

        deviceSyncState = desiredRegistration == nil ? .idle : .synchronized
    }
}
