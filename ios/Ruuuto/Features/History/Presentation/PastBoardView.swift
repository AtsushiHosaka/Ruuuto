import SwiftUI
import UIKit

/// 読み取り用のボード（RCNO-26）。締切後のボードは配置も装飾も変えられないので、表示だけを行う。
///
/// 写真を長押しすると元の写真のプレビューと「大きく見る」、自分の写真なら「取り下げる」を出す（RCNO-14）。
struct PastBoardView: View {
    @State var model: PastBoardViewModel
    let images: PhotoImageCache
    let makeWithdrawal: @MainActor (@escaping @MainActor (UUID) -> Void) -> PhotoWithdrawalViewModel
    @State private var withdrawal: PhotoWithdrawalViewModel?
    @State private var enlarged: BoardPhoto?
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView()
            case .failed:
                ContentUnavailableView {
                    Label { Text("history.load_failed", tableName: "History") } icon: { Image(systemName: "wifi.exclamationmark") }
                } actions: {
                    Button { Task { await model.load() } } label: { Text("history.retry", tableName: "History") }
                }
            case .loaded(let snapshot):
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(snapshot.board)
                        GeometryReader { proxy in
                            canvas(snapshot, width: proxy.size.width)
                        }
                        .aspectRatio(1 / BoardGeometry.aspect, contentMode: .fit)
                    }
                    .padding(16)
                }
            }
        }
        .background(RuuutoPalette.page)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if withdrawal == nil {
                withdrawal = makeWithdrawal { [model, images] photoID in
                    if case .loaded(let s) = model.state, let path = s.photos.first(where: { $0.id == photoID })?.storagePath {
                        Task { await images.remove(path) }
                    }
                    model.removePhoto(photoID)
                }
            }
            if model.state == .loading { await model.load() }
        }
        .modifier(OptionalWithdrawalDialogs(model: withdrawal))
        .fullScreenCover(item: $enlarged) { photo in
            EnlargedPhotoView(path: photo.storagePath, images: images)
        }
    }

    private func header(_ board: BoardSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: board.topic(for: locale))
                .font(RuuutoType.rounded(.title2))
                .foregroundStyle(RuuutoPalette.ink)
            HStack(spacing: 8) {
                Text(weekRange(board))
                if !board.isOpen {
                    Text("history.board.closed", tableName: "History")
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(RuuutoPalette.line.opacity(0.5), in: Capsule())
                }
            }
            .font(RuuutoType.body(.footnote, dynamicTypeSize: dynamicTypeSize))
            .foregroundStyle(RuuutoPalette.sub)
        }
    }

    private func canvas(_ snapshot: BoardSnapshot, width: CGFloat) -> some View {
        let unplaced = snapshot.photos.filter { BoardGeometry.isUnplaced($0.placement) }.map(\.id)
        let items = (snapshot.photos.map(BoardItem.photo) + snapshot.decorations.map(BoardItem.decoration))
            .sorted { BoardGeometry.drawOrder($0.placement, $1.placement) }

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20).fill(RuuutoPalette.ink)
            ForEach(items) { item in
                switch item {
                case .photo(let photo):
                    photoView(photo, unplacedIndex: unplaced.firstIndex(of: photo.id), width: width)
                case .decoration(let decoration):
                    DecorationView(decoration: decoration, boardWidth: width)
                        .position(decorationCenter(decoration, width: width))
                }
            }
        }
        .frame(width: width, height: width * BoardGeometry.aspect)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("history.board.photos \(snapshot.photos.count)", tableName: "History"))
    }

    /// ペンの点はボード上の位置そのものなので、線全体をボードの中心に置く
    private func decorationCenter(_ d: BoardDecoration, width: CGFloat) -> CGPoint {
        if case .pen = d.content { return CGPoint(x: width / 2, y: width * BoardGeometry.aspect / 2) }
        return BoardGeometry.center(of: d.placement, unplacedIndex: nil, boardWidth: width)
    }

    private func photoView(_ photo: BoardPhoto, unplacedIndex: Int?, width: CGFloat) -> some View {
        let size = BoardGeometry.photoSize(width: photo.width, height: photo.height, scale: photo.placement.scale, boardWidth: width)
        return StoredPhotoImage(path: photo.storagePath, images: images)
            .frame(width: size.width, height: size.height)
            .clipped()
            .padding(4)
            .background(Color.white)
            .photoContextMenu(
                target: .init(photoID: photo.id, storagePath: photo.storagePath),
                postedBy: photo.postedBy,
                withdrawal: withdrawal,
                onViewLarger: { enlarged = photo }
            ) {
                // 長押しのプレビューは元の色の写真（RCNO-28 の退色をかけない）
                StoredPhotoImage(path: photo.storagePath, images: images, contentMode: .fit)
                    .frame(width: 320, height: 320 * size.height / max(size.width, 1))
            }
            .rotationEffect(.degrees(photo.placement.rotation))
            .position(BoardGeometry.center(of: photo.placement, unplacedIndex: unplacedIndex, boardWidth: width))
            .accessibilityLabel(Text("history.board.photo", tableName: "History"))
    }
}

private enum BoardItem: Identifiable {
    case photo(BoardPhoto)
    case decoration(BoardDecoration)

    var id: UUID {
        switch self {
        case .photo(let p): p.id
        case .decoration(let d): d.id
        }
    }

    var placement: BoardPlacement {
        switch self {
        case .photo(let p): p.placement
        case .decoration(let d): d.placement
        }
    }
}

/// 文字・スタンプ・ペンの表示（読み取りのみ）
struct DecorationView: View {
    let decoration: BoardDecoration
    let boardWidth: CGFloat

    var body: some View {
        let base = BoardGeometry.decorationBaseSize * decoration.placement.scale * boardWidth
        Group {
            switch decoration.content {
            case .text(let text, let color):
                Text(verbatim: text)
                    .font(RuuutoType.hand(.title3))
                    .foregroundStyle(Color(hex: color) ?? .white)
                    .scaleEffect(decoration.placement.scale)
            case .stamp(let id):
                Image(systemName: Self.symbol(for: id))
                    .resizable().scaledToFit()
                    .frame(width: base, height: base)
                    .foregroundStyle(RuuutoPalette.accent)
            case .pen(let strokes):
                PenStrokes(strokes: strokes, boardWidth: boardWidth)
                    .frame(width: boardWidth, height: boardWidth * BoardGeometry.aspect)
            case .unknown:
                EmptyView()
            }
        }
        .rotationEffect(.degrees(decoration.placement.rotation))
        .accessibilityHidden(true)
    }

    /// スタンプの絵柄はボード担当と調整中。決まるまでは SF Symbols の近いものを使う
    static func symbol(for id: String) -> String {
        switch id {
        case "star": "star.fill"
        case "heart": "heart.fill"
        case "sun": "sun.max.fill"
        case "moon": "moon.fill"
        case "snow": "snowflake"
        default: UIImage(systemName: id) == nil ? "seal.fill" : id
        }
    }
}

/// ペンの線。点の座標は BoardGeometry と同じ単位（ボードの幅を1とした割合）として描く
private struct PenStrokes: View {
    let strokes: [BoardDecoration.Stroke]
    let boardWidth: CGFloat

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes where stroke.points.count > 1 {
                var path = Path()
                path.move(to: CGPoint(x: stroke.points[0][0] * boardWidth, y: stroke.points[0][1] * boardWidth))
                for p in stroke.points.dropFirst() { path.addLine(to: CGPoint(x: p[0] * boardWidth, y: p[1] * boardWidth)) }
                context.stroke(path, with: .color(Color(hex: stroke.colorHex) ?? .white),
                               style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// 写真を画面いっぱいに表示する（長押しメニューの「大きく見る」）
struct EnlargedPhotoView: View {
    let path: String
    let images: PhotoImageCache
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StoredPhotoImage(path: path, images: images, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text("photos.common.close", tableName: "Photos") }
                    }
                }
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private struct OptionalWithdrawalDialogs: ViewModifier {
    let model: PhotoWithdrawalViewModel?

    func body(content: Content) -> some View {
        if let model { content.photoWithdrawalDialogs(model) } else { content }
    }
}

extension Color {
    /// "#RRGGBB" の色。読めなければ nil
    init?(hex: String?) {
        guard var hex, hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
