import Foundation
import Observation

@MainActor
@Observable
final class GroupDirectoryViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    private(set) var groups: [BoardGroup] = []
    private(set) var selectedID: UUID?
    private(set) var loadState: LoadState = .idle

    private let loadGroups: @MainActor () async throws -> [BoardGroup]
    @ObservationIgnored private var activeRequest: UUID?
    @ObservationIgnored private var previousLoadState: LoadState = .idle
    @ObservationIgnored private var membershipsAddedDuringLoad: Set<UUID> = []

    init(loadGroups: @escaping @MainActor () async throws -> [BoardGroup]) {
        self.loadGroups = loadGroups
    }

    func refresh() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        if activeRequest == nil {
            previousLoadState = loadState
            membershipsAddedDuringLoad.removeAll()
        }
        activeRequest = request
        loadState = .loading

        defer {
            if activeRequest == request {
                activeRequest = nil
                membershipsAddedDuringLoad.removeAll()
                if loadState == .loading {
                    loadState = previousLoadState
                }
            }
        }

        do {
            let refreshed = try await loadGroups()
            guard activeRequest == request, !Task.isCancelled else { return }
            let refreshedIDs = Set(refreshed.map(\.id))
            groups = refreshed + groups.filter {
                membershipsAddedDuringLoad.contains($0.id) && !refreshedIDs.contains($0.id)
            }
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard activeRequest == request, !Task.isCancelled else { return }
            loadState = .failed
        }
    }

    func selectGroup(id: UUID) {
        selectedID = id
    }

    func selectGroup(_ group: BoardGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
        }

        // A list request already in progress might predate the confirmed membership.
        if activeRequest != nil {
            membershipsAddedDuringLoad.insert(group.id)
        }
        selectGroup(id: group.id)
    }
}
