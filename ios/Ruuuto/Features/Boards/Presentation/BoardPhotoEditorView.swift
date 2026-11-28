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
    @State private var isTextComposerPresented = false
    @State private var isStampPickerPresented = false
    @State private var isPenEnabled = false
    @State private var selectedStamp: BoardStampKind?
    @State private var textDraft = ""
    @State private var canvasSize = CGSize(width: 320, height: 500)

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

                if editor.state == .loaded {
                    BoardDecorationToolbar(
                        canDecorate: editor.isEditable && !editor.isSavingText && !editor.isSavingPen
                            && !editor.isSavingStamp,
                        isPenEnabled: isPenEnabled,
                        selectedStamp: selectedStamp,
                        addText: {
                            isPenEnabled = false
                            selectedStamp = nil
                            editor.discardPendingPenStroke()
                            editor.discardPendingStamp()
                            editor.dismissTextError()
                            isTextComposerPresented = true
                        },
                        selectStamp: {
                            isPenEnabled = false
                            selectedStamp = nil
                            editor.discardPendingPenStroke()
                            editor.discardPendingStamp()
                            isStampPickerPresented = true
                        },
                        togglePen: {
                            selectedStamp = nil
                            editor.discardPendingStamp()
                            if isPenEnabled {
                                isPenEnabled = false
                                editor.discardPendingPenStroke()
                            } else {
                                isPenEnabled = true
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(RuuutoPalette.page.ignoresSafeArea())
        .task(id: board.id) {
            isPenEnabled = false
            selectedStamp = nil
            editor.discardPendingPenStroke()
            editor.discardPendingStamp()
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
        .sheet(isPresented: $isTextComposerPresented) {
            TextDecorationComposer(
                text: $textDraft,
                isSaving: editor.isSavingText,
                errorMessage: editor.textErrorMessage,
                cancel: {
                    guard !editor.isSavingText else { return }
                    textDraft = ""
                    editor.dismissTextError()
                    isTextComposerPresented = false
                },
                add: submitTextDecoration
            )
            .presentationDetents([.medium])
            .interactiveDismissDisabled(editor.isSavingText)
        }
        .sheet(isPresented: $isStampPickerPresented) {
            StampPicker(
                select: { stamp in
                    selectedStamp = stamp
                    isStampPickerPresented = false
                },
                cancel: {
                    isStampPickerPresented = false
                }
            )
            .presentationDetents([.medium])
        }
        .alert(
            Text("boards.decorations.pen.save_error_title"),
            isPresented: Binding(
                get: { editor.penErrorMessage != nil },
                set: { if !$0 { editor.discardPendingPenStroke() } }
            )
        ) {
            Button("boards.decorations.pen.retry") {
                Task { _ = await editor.retryPendingPenStroke() }
            }
            Button("boards.decorations.pen.discard", role: .destructive) {
                editor.discardPendingPenStroke()
            }
        } message: {
            if let message = editor.penErrorMessage {
                Text(verbatim: message)
            }
        }
        .alert(
            Text("boards.decorations.stamp.save_error_title"),
            isPresented: Binding(
                get: { editor.stampErrorMessage != nil },
                set: { if !$0 { editor.discardPendingStamp() } }
            )
        ) {
            Button("boards.decorations.stamp.retry") {
                Task { _ = await editor.retryPendingStamp() }
            }
            Button("boards.decorations.stamp.discard", role: .destructive) {
                editor.discardPendingStamp()
            }
        } message: {
            if let message = editor.stampErrorMessage {
                Text(verbatim: message)
            }
        }
    }

    private func submitTextDecoration() {
        let origin = CGPoint(
            x: max(12, (canvasSize.width - 220) / 2),
            y: max(12, (canvasSize.height - 44) / 2)
        )
        Task {
            if await editor.addText(
                textDraft,
                x: BoardCoordinateConverter.normalized(origin.x, length: canvasSize.width),
                y: BoardCoordinateConverter.normalized(origin.y, length: canvasSize.height)
            ) {
                textDraft = ""
                isTextComposerPresented = false
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
        case .loaded:
            BoardPhotoCanvas(
                editor: editor,
                presence: presence,
                isPenEnabled: isPenEnabled,
                selectedStamp: $selectedStamp
            )
                .frame(height: 500)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: BoardCanvasSizePreferenceKey.self, value: proxy.size)
                    }
                }
                .onPreferenceChange(BoardCanvasSizePreferenceKey.self) { size in
                    guard size.width > 0, size.height > 0 else { return }
                    canvasSize = size
                }
        }
    }
}

private struct BoardPhotoCanvas: View {
    @Bindable var editor: BoardPhotoEditorViewModel
    @Bindable var presence: BoardPresenceViewModel
    let isPenEnabled: Bool
    @Binding var selectedStamp: BoardStampKind?
    @State private var dragTranslations: [UUID: CGSize] = [:]
    @State private var pendingOrigins: [UUID: CGPoint] = [:]
    @State private var draftPenPoints: [BoardPenPoint] = []

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            ZStack(alignment: .topLeading) {
                BoardDotGrid()

                if editor.photos.isEmpty, editor.textDecorations.isEmpty, editor.penDecorations.isEmpty,
                   editor.stampDecorations.isEmpty {
                    Text("boards.photos.empty")
                        .foregroundStyle(RuuutoPalette.soft)
                        .multilineTextAlignment(.center)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                }

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

                ForEach(canvasDecorations) { decoration in
                    switch decoration {
                    case .text(let text):
                        BoardTextDecorationView(decoration: text)
                            .offset(
                                x: BoardCoordinateConverter.screen(text.x, length: canvasSize.width),
                                y: BoardCoordinateConverter.screen(text.y, length: canvasSize.height)
                            )
                    case .pen(let pen):
                        BoardPenDecorationView(decoration: pen, canvasSize: canvasSize)
                    case .stamp(let stamp):
                        BoardStampDecorationView(decoration: stamp, canvasSize: canvasSize)
                    }
                }

                if let placement = editor.pendingStampPlacement {
                    BoardStampView(stamp: placement.stamp)
                        .position(
                            x: CGFloat(placement.x) * canvasSize.width,
                            y: CGFloat(placement.y) * canvasSize.height
                        )
                        .opacity(editor.isSavingStamp ? 0.72 : 1)
                }

                if let pendingPenStroke = editor.pendingPenStroke {
                    BoardPenStrokeView(
                        stroke: BoardPenStroke(points: pendingPenStroke, colorHex: "#6E9BF2", width: 4),
                        canvasSize: canvasSize
                    )
                    .opacity(editor.isSavingPen ? 0.72 : 1)
                }

                if draftPenPoints.count >= 2 {
                    BoardPenStrokeView(
                        stroke: BoardPenStroke(points: draftPenPoints, colorHex: "#6E9BF2", width: 4),
                        canvasSize: canvasSize
                    )
                }

                ForEach(presence.remoteCursors) { cursor in
                    BoardParticipantCursor(displayName: cursor.displayName)
                        .offset(
                            x: CGFloat(cursor.position.x) * canvasSize.width,
                            y: CGFloat(cursor.position.y) * canvasSize.height
                        )
                        .animation(.linear(duration: 0.08), value: cursor.position)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(stampGesture(canvasSize: canvasSize))
                    .allowsHitTesting(
                        selectedStamp != nil && editor.isEditable && !editor.isSavingStamp
                            && editor.pendingStampPlacement == nil
                    )
                    .accessibilityLabel("boards.decorations.stamp.canvas")

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(penGesture(canvasSize: canvasSize))
                    .allowsHitTesting(
                        isPenEnabled && editor.isEditable && !editor.isSavingPen
                            && editor.pendingPenStroke == nil
                    )
                    .accessibilityLabel("boards.decorations.pen.canvas")
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
        .onChange(of: isPenEnabled) { _, enabled in
            if !enabled {
                draftPenPoints = []
                presence.setCursor(nil)
            }
        }
        .onDisappear {
            draftPenPoints = []
            presence.setCursor(nil)
        }
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
                    await editor.commitMove(
                        photoID: photo.id,
                        x: BoardCoordinateConverter.normalized(origin.x, length: canvasSize.width),
                        y: BoardCoordinateConverter.normalized(origin.y, length: canvasSize.height)
                    )
                    pendingOrigins[photo.id] = nil
                    presence.setEditingPhotoID(nil)
                }
            }
    }

    private var canvasDecorations: [BoardCanvasDecoration] {
        (
            editor.textDecorations.map(BoardCanvasDecoration.text)
                + editor.penDecorations.map(BoardCanvasDecoration.pen)
                + editor.stampDecorations.map(BoardCanvasDecoration.stamp)
        ).sorted { ($0.layer, $0.zIndex, $0.id.uuidString) < ($1.layer, $1.zIndex, $1.id.uuidString) }
    }

    private func stampGesture(canvasSize: CGSize) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .named(BoardCanvasCoordinateSpace.name))
            .onEnded { value in
                guard let stamp = selectedStamp else { return }
                selectedStamp = nil
                let x = BoardCoordinateConverter.normalized(value.location.x, length: canvasSize.width)
                let y = BoardCoordinateConverter.normalized(value.location.y, length: canvasSize.height)
                Task { _ = await editor.addStamp(stamp, x: x, y: y) }
            }
    }

    private func penGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(BoardCanvasCoordinateSpace.name))
            .onChanged { value in
                let point = BoardPenPoint(
                    x: BoardCoordinateConverter.normalized(value.location.x, length: canvasSize.width),
                    y: BoardCoordinateConverter.normalized(value.location.y, length: canvasSize.height)
                )
                if let last = draftPenPoints.last {
                    let distance = hypot(point.x - last.x, point.y - last.y)
                    guard distance >= 0.003 else { return }
                }
                draftPenPoints.append(point)
                presence.setCursor(BoardCursorPosition(x: point.x, y: point.y))
            }
            .onEnded { _ in
                presence.setCursor(nil)
                let points = draftPenPoints
                draftPenPoints = []
                guard points.count >= 2 else { return }
                Task { _ = await editor.savePenStroke(points) }
            }
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
        let storedX = BoardCoordinateConverter.screen(photo.x, length: canvasSize.width)
        let storedY = BoardCoordinateConverter.screen(photo.y, length: canvasSize.height)
        return CGPoint(
            x: min(max(storedX + translation.width, 0), maximumX),
            y: min(max(storedY + translation.height, 0), maximumY)
        )
    }
}

private struct BoardCanvasSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct BoardDecorationToolbar: View {
    let canDecorate: Bool
    let isPenEnabled: Bool
    let selectedStamp: BoardStampKind?
    let addText: () -> Void
    let selectStamp: () -> Void
    let togglePen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    decorationButton(
                        title: "boards.decorations.stamp.add",
                        systemImage: "face.smiling",
                        isSelected: selectedStamp != nil,
                        action: selectStamp
                    )

                    decorationButton(
                        title: "boards.decorations.text.add",
                        systemImage: "character.cursor.ibeam",
                        isSelected: false,
                        action: addText
                    )

                    decorationButton(
                        title: isPenEnabled
                            ? "boards.decorations.pen.finish"
                            : "boards.decorations.pen.add",
                        systemImage: "pencil.tip",
                        isSelected: isPenEnabled,
                        action: togglePen
                    )
                }
            }

            if isPenEnabled {
                Text("boards.decorations.pen.instruction")
                    .font(.caption)
                    .foregroundStyle(RuuutoPalette.muted)
            } else if let selectedStamp {
                HStack(spacing: 6) {
                    Text(verbatim: selectedStamp.symbol)
                    Text("boards.decorations.stamp.instruction")
                }
                .font(.caption)
                .foregroundStyle(RuuutoPalette.muted)
            }
        }
        .padding(.horizontal, 4)
    }

    private func decorationButton(
        title: LocalizedStringKey,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(RuuutoType.rounded(.caption).bold())
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(isSelected ? RuuutoPalette.accent : RuuutoPalette.soft.opacity(0.55))
                .foregroundStyle(isSelected ? Color.white : RuuutoPalette.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canDecorate)
        .opacity(canDecorate ? 1 : 0.45)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct StampPicker: View {
    let select: (BoardStampKind) -> Void
    let cancel: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 92), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(BoardStampKind.allCases) { stamp in
                        Button {
                            select(stamp)
                        } label: {
                            VStack(spacing: 8) {
                                Text(verbatim: stamp.symbol)
                                    .font(.system(size: 42))
                                Text(LocalizedStringKey("boards.decorations.stamp.option.\(stamp.rawValue)"))
                                    .font(RuuutoType.rounded(.caption))
                                    .foregroundStyle(RuuutoPalette.ink)
                            }
                            .frame(maxWidth: .infinity, minHeight: 92)
                            .background(RuuutoPalette.soft.opacity(0.42))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Text(LocalizedStringKey("boards.decorations.stamp.option.\(stamp.rawValue)"))
                        )
                    }
                }
                .padding(16)
            }
            .navigationTitle("boards.decorations.stamp.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("boards.decorations.stamp.cancel", action: cancel)
                }
            }
        }
    }
}

private struct TextDecorationComposer: View {
    @Binding var text: String
    let isSaving: Bool
    let errorMessage: String?
    let cancel: () -> Void
    let add: () -> Void

    private var canAdd: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 200 && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("boards.decorations.text.placeholder", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .disabled(isSaving)

                    HStack {
                        Spacer()
                        Text(verbatim: "\(text.count)/200")
                            .font(.caption)
                            .foregroundStyle(text.count <= 200 ? RuuutoPalette.muted : .red)
                    }
                } header: {
                    Text("boards.decorations.text.input_title")
                }

                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("boards.decorations.text.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("boards.decorations.text.cancel", action: cancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel("boards.decorations.text.saving")
                    } else {
                        Button("boards.decorations.text.confirm", action: add)
                            .disabled(!canAdd)
                    }
                }
            }
        }
    }
}

private struct BoardTextDecorationView: View {
    let decoration: BoardTextDecoration

    var body: some View {
        Text(verbatim: decoration.text)
            .font(RuuutoType.hand(.title3))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 220)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(decorationColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
            .rotationEffect(.degrees(decoration.rotation))
            .scaleEffect(decoration.scale)
            .allowsHitTesting(false)
            .accessibilityLabel(Text(verbatim: decoration.text))
    }

    private var decorationColor: Color {
        let hex = decoration.colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return RuuutoPalette.accent }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

private enum BoardCanvasDecoration: Identifiable {
    case text(BoardTextDecoration)
    case pen(BoardPenDecoration)
    case stamp(BoardStampDecoration)

    var id: UUID {
        switch self {
        case .text(let decoration): decoration.id
        case .pen(let decoration): decoration.id
        case .stamp(let decoration): decoration.id
        }
    }

    var layer: Int {
        switch self {
        case .text(let decoration): decoration.layer
        case .pen(let decoration): decoration.layer
        case .stamp(let decoration): decoration.layer
        }
    }

    var zIndex: Int {
        switch self {
        case .text(let decoration): decoration.zIndex
        case .pen(let decoration): decoration.zIndex
        case .stamp(let decoration): decoration.zIndex
        }
    }
}

private struct BoardStampDecorationView: View {
    let decoration: BoardStampDecoration
    let canvasSize: CGSize

    var body: some View {
        BoardStampView(stamp: decoration.stamp)
            .rotationEffect(.degrees(decoration.rotation))
            .scaleEffect(decoration.scale)
            .position(
                x: BoardCoordinateConverter.screen(decoration.x, length: canvasSize.width),
                y: BoardCoordinateConverter.screen(decoration.y, length: canvasSize.height)
            )
    }
}

private struct BoardStampView: View {
    let stamp: BoardStampKind

    var body: some View {
        Text(verbatim: stamp.symbol)
            .font(.system(size: 48))
            .shadow(color: .black.opacity(0.24), radius: 5, y: 3)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityLabel(
                Text(LocalizedStringKey("boards.decorations.stamp.option.\(stamp.rawValue)"))
            )
    }
}

private struct BoardPenDecorationView: View {
    let decoration: BoardPenDecoration
    let canvasSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(decoration.strokes.enumerated()), id: \.offset) { _, stroke in
                BoardPenStrokeView(stroke: stroke, canvasSize: canvasSize)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .rotationEffect(.degrees(decoration.rotation))
        .scaleEffect(decoration.scale)
        .offset(
            x: BoardCoordinateConverter.screen(decoration.x, length: canvasSize.width),
            y: BoardCoordinateConverter.screen(decoration.y, length: canvasSize.height)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BoardPenStrokeView: View {
    let stroke: BoardPenStroke
    let canvasSize: CGSize

    var body: some View {
        Path { path in
            guard let first = stroke.points.first else { return }
            path.move(to: screenPoint(first))
            for point in stroke.points.dropFirst() {
                path.addLine(to: screenPoint(point))
            }
        }
        .stroke(
            strokeColor,
            style: StrokeStyle(
                lineWidth: CGFloat(stroke.width),
                lineCap: .round,
                lineJoin: .round
            )
        )
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func screenPoint(_ point: BoardPenPoint) -> CGPoint {
        CGPoint(
            x: CGFloat(point.x) * canvasSize.width,
            y: CGFloat(point.y) * canvasSize.height
        )
    }

    private var strokeColor: Color {
        let hex = stroke.colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return RuuutoPalette.accent }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
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
