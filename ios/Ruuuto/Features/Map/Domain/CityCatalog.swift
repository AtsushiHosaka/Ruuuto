// logic-test
import Foundation

/// 投稿に付けられる都市と地域（RCNO-29）。
///
/// photos.city には表示名ではなく `id` を保存する（例: `gn:1850147`、`region:US-W`）。
/// 表示名は端末の言語で選ぶので、日本語と英語の端末で同じ都市を同じピンにまとめられる。
/// 緯度経度とタイムゾーンは、マップのピンの位置と現地時刻（RCNO-31）に使う。
struct City: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let ja: String
    let en: String
    /// ISO 3166-1 alpha-2
    let country: String
    let lat: Double
    let lng: Double
    /// IANA のタイムゾーン名
    let tz: String

    /// 一覧にない場所のための「国名 + 北部・南部・東部・西部・中部」
    var isRegion: Bool { id.hasPrefix("region:") }

    func name(for locale: Locale) -> String {
        locale.language.languageCode?.identifier == "ja" ? ja : en
    }

    var timeZone: TimeZone? { TimeZone(identifier: tz) }
}

struct CityCatalog: Sendable {
    let cities: [City]
    let regions: [City]
    private let byID: [String: City]

    init(cities: [City], regions: [City]) {
        self.cities = cities
        self.regions = regions
        byID = Dictionary((cities + regions).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(json: Data) throws {
        struct File: Decodable { let cities: [City]; let regions: [City] }
        let file = try JSONDecoder().decode(File.self, from: json)
        self.init(cities: file.cities, regions: file.regions)
    }

    /// アプリに同梱した一覧（Features/Map/Data/cities.json）。出典は GeoNames（CC BY 4.0）と Wikidata（CC0）。
    static let bundled: CityCatalog = {
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? CityCatalog(json: data)
        else { return CityCatalog(cities: [], regions: []) }
        return catalog
    }()

    func city(id: String) -> City? { byID[id] }

    /// 日本語名・英語名のどちらでも探せる。前方一致を先に、部分一致を後に並べ、
    /// それぞれの中では端末の地域（preferredCountry）の都市を先にする。
    /// 空の検索では端末の地域の都市を返す（一覧は国ごとに人口の多い順）。
    func search(_ query: String, preferredCountry: String? = nil, limit: Int = 50) -> [City] {
        let q = Self.normalize(query)
        let preferred = { (city: City) in city.country == preferredCountry }
        guard !q.isEmpty else {
            let local = cities.filter(preferred)
            return Array((local.isEmpty ? cities : local).prefix(limit))
        }

        var prefix: [City] = [], contains: [City] = []
        for city in cities + regions {
            let names = [Self.normalize(city.ja), Self.normalize(city.en)]
            if names.contains(where: { $0.hasPrefix(q) }) {
                prefix.append(city)
            } else if names.contains(where: { $0.contains(q) }) {
                contains.append(city)
            }
        }
        let ranked = prefix.filter(preferred) + prefix.filter { !preferred($0) }
            + contains.filter(preferred) + contains.filter { !preferred($0) }
        return Array(ranked.prefix(limit))
    }

    /// 大文字小文字、アクセント、ひらがなとカタカナの違いを無視する
    static func normalize(_ text: String) -> String {
        let folded = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
    }
}
