import MapKit
import SwiftUI

extension CityMapViewModel: Identifiable {}

/// 都市別マップ（RCNO-31）。原案 HTML の「マップ（どこから投稿したか）」に合わせ、都市ごとのピンに写真の数を表示する。
/// ピンを選ぶと、その都市の現地時刻と写真の一覧をシートに表示する。
struct CityMapView: View {
    @State var model: CityMapViewModel
    let images: PhotoImageCache
    let makeWithdrawal: @MainActor (@escaping @MainActor (UUID) -> Void) -> PhotoWithdrawalViewModel
    @State private var camera: MapCameraPosition = .automatic
    @State private var withdrawal: PhotoWithdrawalViewModel?
    @State private var enlarged: CityPhoto?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            Map(position: $camera) {
                ForEach(model.mappedPins) { pin in
                    if let city = pin.city {
                        Annotation(city.name(for: locale), coordinate: CLLocationCoordinate2D(latitude: city.lat, longitude: city.lng)) {
                            Button {
                                Task { await model.select(pin.cityID) }
                            } label: {
                                pinView(pin)
                            }
                            .accessibilityLabel(Text("map.pin \(city.name(for: locale)) \(pin.photoCount)", tableName: "Map"))
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .overlay { emptyOverlay }
            .navigationTitle(Text("map.title", tableName: "Map"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("map.close", tableName: "Map") }
                }
            }
            .sheet(isPresented: Binding(get: { model.selectedCityID != nil }, set: { if !$0 { Task { await model.select(nil) } } })) {
                citySheet
                    .presentationDetents([.medium, .large])
                    .modifier(MapWithdrawalDialogs(model: withdrawal))
                    .fullScreenCover(item: $enlarged) { photo in
                        EnlargedPhotoView(path: photo.storagePath, images: images)
                    }
            }
            .task {
                if withdrawal == nil {
                    withdrawal = makeWithdrawal { [model, images] photoID in
                        if case .loaded(let list) = model.photos, let path = list.first(where: { $0.id == photoID })?.storagePath {
                            Task { await images.remove(path) }
                        }
                        model.removePhoto(photoID)
                    }
                }
                if model.state == .loading { await model.reload() }
            }
        }
    }

    private func pinView(_ pin: CityMapViewModel.Pin) -> some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(RuuutoPalette.accent)
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                .overlay(Image(systemName: "photo.fill").foregroundStyle(.white))
            Text(verbatim: "\(pin.photoCount)")
                .font(RuuutoType.rounded(.caption))
                .foregroundStyle(RuuutoPalette.ink)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.white, in: Capsule())
                .offset(x: 8, y: -6)
        }
    }

    @ViewBuilder private var emptyOverlay: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .failed:
            ContentUnavailableView {
                Label { Text("map.load_failed", tableName: "Map") } icon: { Image(systemName: "wifi.exclamationmark") }
            } actions: {
                Button { Task { await model.reload() } } label: { Text("map.retry", tableName: "Map") }
            }
            .background(.regularMaterial)
        case .loaded where model.mappedPins.isEmpty:
            ContentUnavailableView {
                Label { Text("map.empty.title", tableName: "Map") } icon: { Image(systemName: "mappin.slash") }
            } description: {
                Text("map.empty.message", tableName: "Map")
            }
            .background(.regularMaterial)
        case .loaded:
            EmptyView()
        }
    }

    @ViewBuilder private var citySheet: some View {
        NavigationStack {
            Group {
                switch model.photos {
                case .loading:
                    ProgressView()
                case .failed:
                    ContentUnavailableView {
                        Label { Text("map.load_failed", tableName: "Map") } icon: { Image(systemName: "wifi.exclamationmark") }
                    } actions: {
                        Button { Task { await model.select(model.selectedCityID) } } label: { Text("map.retry", tableName: "Map") }
                    }
                case .loaded(let photos) where photos.isEmpty:
                    ContentUnavailableView {
                        Label { Text("map.city.empty", tableName: "Map") } icon: { Image(systemName: "photo") }
                    }
                case .loaded(let photos):
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                            ForEach(photos) { photo in photoCell(photo) }
                        }
                        .padding(16)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { sheetTitle }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private var sheetTitle: some View {
        if let pin = model.selectedPin {
            HStack(spacing: 8) {
                Text(verbatim: pin.city?.name(for: locale) ?? pin.cityID)
                    .font(RuuutoType.rounded(.headline))
                if let tz = pin.city?.timeZone {
                    LocalTimeLabel(timeZone: tz)
                }
                Text("map.city.count \(pin.photoCount)", tableName: "Map")
                    .font(RuuutoType.body(.caption, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(RuuutoPalette.sub)
            }
        }
    }

    private func photoCell(_ photo: CityPhoto) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            StoredPhotoImage(path: photo.storagePath, images: images)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .photoContextMenu(
                    target: .init(photoID: photo.id, storagePath: photo.storagePath),
                    postedBy: photo.postedBy,
                    withdrawal: withdrawal,
                    onViewLarger: { enlarged = photo }
                ) {
                    StoredPhotoImage(path: photo.storagePath, images: images, contentMode: .fit)
                        .frame(width: 320, height: 320)
                }
                .accessibilityLabel(Text("map.photo.label \(photo.displayName)", tableName: "Map"))
            Text(verbatim: photo.displayName)
                .font(RuuutoType.hand(.caption))
                .foregroundStyle(RuuutoPalette.sub)
                .lineLimit(1)
        }
    }
}

/// 都市の現地時刻と、昼夜の記号（原案 HTML のシートの表示）
private struct LocalTimeLabel: View {
    let timeZone: TimeZone

    var body: some View {
        TimelineView(.everyMinute) { context in
            let hour = Self.calendar(timeZone).component(.hour, from: context.date)
            HStack(spacing: 4) {
                Image(systemName: (6..<18).contains(hour) ? "sun.max.fill" : "moon.fill")
                    .accessibilityHidden(true)
                Text(context.date, format: Self.style(timeZone))
            }
            .font(RuuutoType.rounded(.subheadline))
        }
    }

    private static func calendar(_ tz: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return calendar
    }

    private static func style(_ tz: TimeZone) -> Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = tz
        return style
    }
}

private struct MapWithdrawalDialogs: ViewModifier {
    let model: PhotoWithdrawalViewModel?

    func body(content: Content) -> some View {
        if let model { content.photoWithdrawalDialogs(model) } else { content }
    }
}
