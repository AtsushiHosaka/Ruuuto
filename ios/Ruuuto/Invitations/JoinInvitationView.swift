import SwiftUI

enum InvitationJoinError: Error {
    case invalid
    case expired
}

struct JoinInvitationView: View {
    enum State: Equatable {
        case ready
        case joining
        case accepted
        case invalid
        case expired
        case failed
    }

    let signedIn: Bool
    let signIn: () -> Void
    let join: () async throws -> Void

    @State private var state: State = .ready

    var body: some View {
        Form {
            Section("グループへの招待") {
                if !signedIn {
                    Text("ログインすると、この招待からグループに参加できます。")
                    Button("ログインへ進む", action: signIn)
                } else {
                    switch state {
                    case .ready:
                        Button("グループに参加") { Task { await accept() } }
                    case .joining:
                        ProgressView("参加中")
                    case .accepted:
                        Label("参加しました", systemImage: "checkmark.circle")
                    case .invalid:
                        Text("この招待リンクは無効です。新しいリンクを受け取ってください。")
                    case .expired:
                        Text("この招待リンクの期限が切れています。新しいリンクを受け取ってください。")
                    case .failed:
                        Text("参加できませんでした。通信を確認してください。")
                        Button("再試行") { Task { await accept() } }
                    }
                }
            }
        }
        .navigationTitle("招待")
    }

    private func accept() async {
        guard signedIn, state == .ready || state == .failed else { return }
        state = .joining
        do {
            try await join()
            state = .accepted
        } catch InvitationJoinError.invalid {
            state = .invalid
        } catch InvitationJoinError.expired {
            state = .expired
        } catch is CancellationError {
            state = .ready
        } catch {
            state = .failed
        }
    }
}

struct ShareInvitationView: View {
    let invitationURL: URL

    var body: some View {
        ShareLink(item: invitationURL) {
            Label("招待リンクを共有", systemImage: "square.and.arrow.up")
        }
    }
}
