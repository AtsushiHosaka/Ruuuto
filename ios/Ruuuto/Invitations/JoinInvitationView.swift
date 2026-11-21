import SwiftUI

enum InvitationJoinError: Error {
    case invalid
    case expired
}

struct InvitationSummary: Equatable, Sendable {
    let groupName: String
    let memberNames: [String]
    let postcardCaptions: [String]

    init(groupName: String, memberNames: [String], postcardCaptions: [String] = []) {
        self.groupName = groupName
        self.memberNames = memberNames
        self.postcardCaptions = postcardCaptions
    }
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
    let summary: InvitationSummary?
    let signIn: () -> Void
    let join: () async throws -> Void

    @State private var state: State = .ready

    init(
        signedIn: Bool,
        summary: InvitationSummary? = nil,
        signIn: @escaping () -> Void,
        join: @escaping () async throws -> Void
    ) {
        self.signedIn = signedIn
        self.summary = summary
        self.signIn = signIn
        self.join = join
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                postcards

                if let summary {
                    Text(summary.groupName)
                        .font(RuuutoType.rounded(.title2))
                        .accessibilityAddTraits(.isHeader)
                    if !summary.memberNames.isEmpty {
                        avatars(for: summary.memberNames)
                    }
                } else {
                    Text("グループへの招待")
                        .font(RuuutoType.rounded(.title2))
                        .accessibilityAddTraits(.isHeader)
                }

                VStack(spacing: 12) {
                    invitationContent
                }
                .padding(.top, 10)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(RuuutoPalette.ink)
            .frame(maxWidth: 390)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .background(RuuutoPalette.page.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("招待")
                    .font(RuuutoType.rounded(.title3))
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private var postcards: some View {
        let captions = summary?.postcardCaptions ?? []
        return ZStack {
            postcard(
                caption: captions.first,
                colors: (RuuutoPalette.soft, RuuutoPalette.line, RuuutoPalette.accent)
            )
            .rotationEffect(.degrees(-10))
            .offset(x: -41, y: -6)

            postcard(
                caption: captions.dropFirst().first,
                colors: (RuuutoPalette.line, RuuutoPalette.accent, RuuutoPalette.soft)
            )
            .rotationEffect(.degrees(9))
            .offset(x: 41, y: 4)
        }
        .frame(height: 156)
        .accessibilityHidden(true)
    }

    private func postcard(caption: String?, colors: (sky: Color, light: Color, ridge: Color)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            LinearGradient(
                stops: [
                    .init(color: colors.sky, location: 0.12),
                    .init(color: colors.light, location: 0.56),
                    .init(color: colors.ridge, location: 0.57),
                    .init(color: colors.light, location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .frame(height: 91)

            Text(caption ?? "")
                .font(RuuutoType.hand(.caption2))
                .lineLimit(1)
        }
        .frame(width: 96, height: 111, alignment: .topLeading)
        .padding(5)
        .background(.white, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: RuuutoPalette.ink.opacity(0.16), radius: 7, y: 5)
    }

    private func avatars(for members: [String]) -> some View {
        HStack(spacing: -4) {
            ForEach(Array(members.prefix(5).enumerated()), id: \.offset) { entry in
                avatar(String(entry.element.prefix(1)))
            }
            if members.count > 5 {
                avatar("+\(members.count - 5)")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("メンバー\(members.count)人")
    }

    private func avatar(_ label: String) -> some View {
        Text(label)
            .font(RuuutoType.body(.caption2).weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: 25, height: 25)
            .background(RuuutoPalette.line, in: Circle())
            .overlay { Circle().strokeBorder(RuuutoPalette.page, lineWidth: 2) }
    }

    @ViewBuilder
    private var invitationContent: some View {
        if !signedIn {
            Text("ログインすると、この招待からグループに参加できます。")
                .font(RuuutoType.body(.subheadline))
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
                    .frame(minHeight: 48)
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
        .font(RuuutoType.body(.subheadline))
        .foregroundStyle(RuuutoPalette.sub)
        .padding(.vertical, 8)
    }

    private func invitationButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(RuuutoType.rounded(.body))
                Image(systemName: "arrow.right")
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(RuuutoPalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RuuutoPalette.accent, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
