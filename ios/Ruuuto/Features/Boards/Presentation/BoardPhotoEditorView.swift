import SwiftUI

struct CurrentBoardScreen: View {
    @Environment(SignedInWorkspace.self) private var workspace
    let groupID: UUID

    var body: some View {
        switch workspace.currentBoard.state(for: groupID) {
        case .idle, .loading:
            ProgressView("boards.current.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            boardMessage("boards.current.empty")
        case .failed(let message):
            boardMessage(verbatim: message)
        case .loaded(let board):
            BoardPhotoEditorView(
                board: board,
                groupName: workspace.groups.groups.first(where: { $0.id == groupID })?.name ?? "Ruuuto",
                editor: workspace.boardPhotos,
                presence: workspace.boardPresence,
                displayName: displayName,
                showGroups: workspace.showGroups
            )
        }
    }

    private var displayName: String {
        if case .loaded(let profile) = workspace.profile.state {
            return profile.displayName
        }
        return String(localized: "boards.presence.member")
    }

    private func boardMessage(_ key: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            Text(key)
                .multilineTextAlignment(.center)
            Button("boards.current.retry") {
                Task { await workspace.currentBoard.reload(for: groupID) }
            }
            .buttonStyle(.borderedProminent)
            .tint(RuuutoPalette.accent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func boardMessage(verbatim message: String) -> some View {
        VStack(spacing: 16) {
            Text(verbatim: message)
                .multilineTextAlignment(.center)
            Button("boards.current.retry") {
                Task { await workspace.currentBoard.reload(for: groupID) }
            }
            .buttonStyle(.borderedProminent)
            .tint(RuuutoPalette.accent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BoardPhotoEditorView: View {
    let board: CurrentBoard
    let groupName: String
    @Bindable var editor: BoardPhotoEditorViewModel
    @Bindable var presence: BoardPresenceViewModel
    let displayName: String
    let showGroups: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: showGroups) {
                    HStack(spacing: 6) {
                        Text(verbatim: groupName)
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                    }
                    .font(RuuutoType.rounded(.headline))
                }
                .buttonStyle(.plain)
                .foregroundStyle(RuuutoPalette.ink)
                .accessibilityLabel("boards.groups.switch")

                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: board.topic)
                        .font(RuuutoType.rounded(.title))
                        .foregroundStyle(RuuutoPalette.ink)
                    Spacer()
                    Label {
                        Text(board.closesAt, style: .date)
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(RuuutoPalette.muted)
                }

                if editor.state == .loaded, editor.syncState != .connected {
                    Label("boards.photos.syncing", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(RuuutoPalette.muted)
                }

                BoardEditingMembersBar(
                    members: presence.members,
                    currentUserID: presence.currentUserID,
                    isReconnecting: presence.state == .reconnecting
                )

                editorContent
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(RuuutoPalette.page.ignoresSafeArea())
        .task(id: board.id) {
            await editor.synchronize(boardID: board.id)
        }
        .task(id: PresenceTaskID(boardID: board.id, displayName: displayName)) {
            await presence.synchronize(boardID: board.id, displayName: displayName)
        }
        .alert(
            Text("boards.photos.move_error_title"),
            isPresented: Binding(
                get: { editor.moveErrorMessage != nil },
                set: { if !$0 { editor.dismissMoveError() } }
            )
        ) {
            Button("boards.action.close", role: .cancel) {
                editor.dismissMoveError()
            }
        } message: {
            if let message = editor.moveErrorMessage {
                Text(verbatim: message)
            }
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        switch editor.state {
        case .idle, .loading:
            ProgressView("boards.photos.loading")
                .frame(maxWidth: .infinity, minHeight: 360)
        case .failed(let message):
            VStack(spacing: 14) {
                Text(verbatim: message)
                    .multilineTextAlignment(.center)
                Button("boards.current.retry") {
                    Task { await editor.reload() }
                }
                .buttonStyle(.borderedProminent)
                .tint(RuuutoPalette.accent)
            }
            .frame(maxWidth: .infinity, minHeight: 360)
        case .loaded where editor.photos.isEmpty:
            Text("boards.photos.empty")
                .foregroundStyle(RuuutoPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 360)
        case .loaded:
            BoardPhotoCanvas(editor: editor, presence: presence)
                .frame(height: 500)
        }
    }
}

private struct BoardPhotoCanvas: View {
    @Bindable var editor: BoardPhotoEditorViewModel
    @Bindable var presence: BoardPresenceViewModel
    @State private var dragTranslations: [UUID: CGSize] = [:]
    @State private var pendingOrigins: [UUID: CGPoint] = [:]

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            ZStack(alignment: .topLeading) {
                BoardDotGrid()

                ForEach(editor.photos) { photo in
                    let photoSize = cardSize(for: photo)
                    let translation = dragTranslations[photo.id] ?? .zero
                    let draggedOrigin = constrainedOrigin(
                        photo: photo,
                        translation: translation,
                        cardSize: photoSize,
                        canvasSize: canvasSize
                    )
                    let origin = pendingOrigins[photo.id] ?? draggedOrigin

                    BoardPhotoCard(
                        photo: photo,
                        isMoving: editor.activePhotoID == photo.id,
                        isLocked: editor.isLockedByAnotherParticipant(photo)
                    )
                    .frame(width: photoSize.width, height: photoSize.height)
                    .rotationEffect(.degrees(photo.rotation))
                    .position(x: origin.x + photoSize.width / 2, y: origin.y + photoSize.height / 2)
                    .gesture(dragGesture(for: photo, cardSize: photoSize, canvasSize: canvasSize))
                    .allowsHitTesting(editor.isEditable && photo.layer > 0)
                    .accessibilityHint(editor.isEditable ? Text("boards.photos.accessibility.move_hint") : Text(verbatim: ""))
                }

                ForEach(remoteCursorMembers) { member in
                    if let cursor = member.cursor {
                        BoardParticipantCursor(displayName: member.displayName)
                            .offset(
                                x: CGFloat(cursor.x) * canvasSize.width,
                                y: CGFloat(cursor.y) * canvasSize.height
                            )
                            .animation(.linear(duration: 0.08), value: cursor)
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .coordinateSpace(name: BoardCanvasCoordinateSpace.name)
        }
        .background(RuuutoPalette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(RuuutoPalette.soft.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("boards.photos.accessibility.canvas")
    }

    private func dragGesture(for photo: BoardPhoto, cardSize: CGSize, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(BoardCanvasCoordinateSpace.name))
            .onChanged { value in
                if dragTranslations[photo.id] == nil {
                    guard editor.beginMoving(photo.id) else { return }
                    presence.setEditingPhotoID(photo.id)
                }
                dragTranslations[photo.id] = value.translation
                presence.setCursor(
                    BoardCursorPosition(
                        x: Double(value.location.x / max(canvasSize.width, 1)),
                        y: Double(value.location.y / max(canvasSize.height, 1))
                    )
                )
            }
            .onEnded { value in
                guard dragTranslations.removeValue(forKey: photo.id) != nil else { return }
                presence.setCursor(nil)
                let origin = constrainedOrigin(
                    photo: photo,
                    translation: value.translation,
                    cardSize: cardSize,
                    canvasSize: canvasSize
                )
                pendingOrigins[photo.id] = origin
                Task {
                    await editor.commitMove(photoID: photo.id, x: Double(origin.x), y: Double(origin.y))
                    pendingOrigins[photo.id] = nil
                    presence.setEditingPhotoID(nil)
                }
            }
    }

    private var remoteCursorMembers: [BoardEditingMember] {
        presence.members.filter { $0.id != presence.currentUserID && $0.cursor != nil }
    }

    private func cardSize(for photo: BoardPhoto) -> CGSize {
        let width = CGFloat(142 * min(max(photo.scale, 0.6), 2.25))
        let imageHeight = min(max(width / CGFloat(photo.aspectRatio), 92), 180)
        return CGSize(width: width, height: imageHeight + 30)
    }

    private func constrainedOrigin(
        photo: BoardPhoto,
        translation: CGSize,
        cardSize: CGSize,
        canvasSize: CGSize
    ) -> CGPoint {
        let maximumX = max(0, canvasSize.width - cardSize.width)
        let maximumY = max(0, canvasSize.height - cardSize.height)
        return CGPoint(
            x: min(max(CGFloat(photo.x) + translation.width, 0), maximumX),
            y: min(max(CGFloat(photo.y) + translation.height, 0), maximumY)
        )
    }
}

private enum BoardCanvasCoordinateSpace {
    static let name = "board-photo-canvas"
}

private struct BoardParticipantCursor: View {
    let displayName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "cursorarrow")
                .font(.title3.weight(.bold))
                .foregroundStyle(RuuutoPalette.accent)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)

            Text(verbatim: displayName)
                .font(RuuutoType.rounded(.caption2).bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RuuutoPalette.accent)
                .clipShape(Capsule())
        }
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(verbatim: String(format: String(localized: "boards.presence.cursor"), displayName))
        )
    }
}

private struct PresenceTaskID: Hashable {
    let boardID: UUID
    let displayName: String
}

private struct BoardEditingMembersBar: View {
    let members: [BoardEditingMember]
    let currentUserID: UUID?
    let isReconnecting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("boards.presence.title")
                    .font(RuuutoType.rounded(.subheadline))
                    .foregroundStyle(RuuutoPalette.ink)
                if isReconnecting {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("boards.presence.reconnecting")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(members) { member in
                        HStack(spacing: 7) {
                            Text(verbatim: initial(for: member.displayName))
                                .font(RuuutoType.rounded(.caption).bold())
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(RuuutoPalette.accent)
                                .clipShape(Circle())

                            Text(verbatim: member.displayName)
                                .font(.caption)
                                .lineLimit(1)

                            if member.id == currentUserID {
                                Text("boards.presence.you")
                                    .font(.caption2)
                                    .foregroundStyle(RuuutoPalette.muted)
                            }

                            if member.editingPhotoID != nil {
                                Image(systemName: "hand.draw.fill")
                                    .font(.caption2)
                                    .foregroundStyle(RuuutoPalette.accent)
                                    .accessibilityLabel("boards.presence.moving_photo")
                            }
                        }
                        .foregroundStyle(RuuutoPalette.ink)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(.white.opacity(0.9))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func initial(for displayName: String) -> String {
        String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

private struct BoardPhotoCard: View {
    let photo: BoardPhoto
    let isMoving: Bool
    let isLocked: Bool

    var body: some View {
        VStack(spacing: 0) {
            AsyncImage(url: photo.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(RuuutoPalette.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RuuutoPalette.soft)
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RuuutoPalette.soft)
                }
            }
            .clipped()

            HStack(spacing: 5) {
                Image(systemName: isLocked ? "lock.fill" : "photo.fill")
                    .font(.caption2)
                Text(verbatim: photo.city ?? String(localized: "boards.photos.city_unknown"))
                    .font(RuuutoType.hand(.caption))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(RuuutoPalette.ink)
            .padding(.horizontal, 7)
            .frame(height: 30)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(isMoving ? 0.34 : 0.22), radius: isMoving ? 13 : 7, y: 5)
        .scaleEffect(isMoving ? 1.035 : 1)
        .opacity(isLocked ? 0.72 : 1)
        .animation(.easeOut(duration: 0.16), value: isMoving)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isLocked ? Text("boards.photos.accessibility.locked_photo") : Text("boards.photos.accessibility.photo")
        )
        .accessibilityValue(Text(verbatim: photo.city ?? String(localized: "boards.photos.city_unknown")))
    }
}

private struct BoardDotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            for x in stride(from: spacing / 2, through: size.width, by: spacing) {
                for y in stride(from: spacing / 2, through: size.height, by: spacing) {
                    let dot = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                    context.fill(Path(ellipseIn: dot), with: .color(RuuutoPalette.soft.opacity(0.5)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
