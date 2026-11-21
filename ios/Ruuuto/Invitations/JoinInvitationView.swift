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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "link")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(RuuutoPalette.ink)
                    .padding(14)
                    .background(RuuutoPalette.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)

                Text("グループへの招待")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(RuuutoPalette.ink)
                    .accessibilityAddTraits(.isHeader)

                invitationContent
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
        .navigationTitle("招待")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var invitationContent: some View {
        if !signedIn {
            Text("ログインすると、この招待からグループに参加できます。")
                .foregroundStyle(RuuutoPalette.sub)
            invitationButton("ログインへ進む", action: signIn)
        } else {
            switch state {
            case .ready:
                invitationButton("グループに参加") { Task { await accept() } }
            case .joining:
                ProgressView("参加中")
                    .tint(RuuutoPalette.ink)
                    .foregroundStyle(RuuutoPalette.ink)
                    .padding(.vertical, 8)
            case .accepted:
                invitationStatus("参加しました", icon: "checkmark.circle")
            case .invalid:
                invitationStatus("この招待リンクは無効です。新しいリンクを受け取ってください。", icon: "exclamationmark.circle")
            case .expired:
                invitationStatus("この招待リンクの期限が切れています。新しいリンクを受け取ってください。", icon: "clock")
            case .failed:
                invitationStatus("参加できませんでした。通信を確認してください。", icon: "exclamationmark.circle")
                invitationButton("再試行") { Task { await accept() } }
            }
        }
    }

    private func invitationStatus(_ title: LocalizedStringKey, icon: String) -> some View {
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

    private func invitationButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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
