// logic-test
import Foundation

/// 送れなかった写真を端末に残しておく（RCNO-15）。
///
/// 表示言語を変えるとiOSはアプリを起動し直すので、メモリ上の状態は消える。
/// 失敗した写真（位置情報を消したアップロード用の画像）と投稿IDをここに保存し、
/// 次に同じボードの投稿画面を開いたときに戻す。同じIDで送り直すので、写真は重複しない。
///
/// 保存先は Application Support/PendingPhotos/<利用者ID>/。利用者ごとに分け、
/// 別のアカウントでサインインした人には見せない。バックアップの対象から外す。
struct PendingPhotoStore: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let photoID: UUID
        let boardID: UUID
        let width: Int
        let height: Int
        let savedAt: Date
    }

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    static func forUser(_ userID: UUID, fileManager: FileManager = .default) -> PendingPhotoStore? {
        guard let base = try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return PendingPhotoStore(
            directory: base.appendingPathComponent("PendingPhotos", isDirectory: true)
                .appendingPathComponent(userID.uuidString, isDirectory: true)
        )
    }

    /// そのボードで最後に失敗した写真。画像か記録のどちらかが欠けていれば消して nil を返す。
    func latest(boardID: UUID) -> (Entry, PreparedPhoto)? {
        let entries = allEntries().filter { $0.boardID == boardID }.sorted { $0.savedAt > $1.savedAt }
        for entry in entries {
            if let data = try? Data(contentsOf: imageURL(entry.photoID)) {
                return (entry, PreparedPhoto(data: data, width: entry.width, height: entry.height))
            }
            remove(photoID: entry.photoID)
        }
        return nil
    }

    func save(photoID: UUID, boardID: UUID, photo: PreparedPhoto, now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)

        let entry = Entry(photoID: photoID, boardID: boardID, width: photo.width, height: photo.height, savedAt: now)
        try photo.data.write(to: imageURL(photoID), options: [.atomic, .completeFileProtection])
        try JSONEncoder().encode(entry).write(to: entryURL(photoID), options: [.atomic, .completeFileProtection])
    }

    func remove(photoID: UUID) {
        try? FileManager.default.removeItem(at: imageURL(photoID))
        try? FileManager.default.removeItem(at: entryURL(photoID))
    }

    private func allEntries() -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
        }
    }

    private func imageURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).jpg") }
    private func entryURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }
}
