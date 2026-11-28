// logic-test
import Foundation
import Observation

/// 都市ごとの写真の数（ruuuto_board_cities）。都市が未設定の写真はサーバーが含めない
struct CityCount: Equatable, Sendable {
    let cityID: String
    let photoCount: Int
}

/// 都市を選んだときの写真（ruuuto_city_photos）
struct CityPhoto: Identifiable, Equatable, Sendable {
    let id: UUID
    let storagePath: String
    let postedBy: UUID
    let displayName: String
    let postedAt: Date
    let width: Int?
    let height: Int?
}

/// 都市別マップ（RCNO-31）。範囲は1つのボード（サーバーの関数がボード単位のため）。
///
/// ボードを切り替えたら前のピンを消し、選んだボードのデータを取り直す。
/// 切り替えたあとに前のボードの結果が届いても使わない。
@MainActor
@Observable
final class CityMapViewModel {
    struct Pin: Identifiable, Equatable, Sendable {
        var id: String { cityID }
        let cityID: String
        /// 一覧にない ID（以前の自由入力など）は nil。地図には置けないので一覧だけに出す
        let city: City?
        let photoCount: Int
    }

    enum State: Equatable {
        case loading
        case loaded([Pin])
        case failed
    }

    enum PhotosState: Equatable {
        case loading
        case loaded([CityPhoto])
        case failed
    }

    private(set) var boardID: UUID
    private(set) var state: State = .loading
    private(set) var selectedCityID: String?
    private(set) var photos: PhotosState = .loading

    private let catalog: CityCatalog
    private let loadCities: @MainActor (UUID) async throws -> [CityCount]
    private let loadPhotos: @MainActor (UUID, String) async throws -> [CityPhoto]
    @ObservationIgnored private var boardRequest = UUID()
    @ObservationIgnored private var photosRequest = UUID()

    init(
        boardID: UUID,
        catalog: CityCatalog,
        loadCities: @escaping @MainActor (UUID) async throws -> [CityCount],
        loadPhotos: @escaping @MainActor (UUID, String) async throws -> [CityPhoto]
    ) {
        self.boardID = boardID
        self.catalog = catalog
        self.loadCities = loadCities
        self.loadPhotos = loadPhotos
    }

    var pins: [Pin] {
        if case .loaded(let pins) = state { return pins }
        return []
    }

    /// 地図に置けるピン（一覧にある都市と地域）
    var mappedPins: [Pin] { pins.filter { $0.city != nil } }

    var selectedPin: Pin? { pins.first { $0.cityID == selectedCityID } }

    func switchBoard(_ newBoardID: UUID) async {
        boardID = newBoardID
        selectedCityID = nil
        photos = .loading
        state = .loading
        await reload()
    }

    func reload() async {
        let request = UUID()
        boardRequest = request
        let board = boardID
        do {
            let counts = try await loadCities(board)
            guard boardRequest == request else { return }
            state = .loaded(counts.filter { $0.photoCount > 0 }.map {
                Pin(cityID: $0.cityID, city: catalog.city(id: $0.cityID), photoCount: $0.photoCount)
            })
        } catch is CancellationError {
            return
        } catch {
            guard boardRequest == request else { return }
            state = .failed
        }
    }

    func select(_ cityID: String?) async {
        selectedCityID = cityID
        guard let cityID else { return }
        let request = UUID()
        photosRequest = request
        photos = .loading
        let board = boardID
        do {
            let list = try await loadPhotos(board, cityID)
            guard photosRequest == request, boardID == board else { return }
            photos = .loaded(list)
        } catch is CancellationError {
            return
        } catch {
            guard photosRequest == request else { return }
            photos = .failed
        }
    }

    /// 取り下げた写真を一覧とピンの数から外す（RCNO-14）
    func removePhoto(_ photoID: UUID) {
        guard case .loaded(let list) = photos, list.contains(where: { $0.id == photoID }) else { return }
        photos = .loaded(list.filter { $0.id != photoID })
        guard let cityID = selectedCityID, case .loaded(let pins) = state else { return }
        state = .loaded(pins.compactMap { pin in
            guard pin.cityID == cityID else { return pin }
            return pin.photoCount > 1 ? Pin(cityID: pin.cityID, city: pin.city, photoCount: pin.photoCount - 1) : nil
        })
    }
}
