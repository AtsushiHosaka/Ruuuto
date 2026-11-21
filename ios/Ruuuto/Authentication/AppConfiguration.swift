import Foundation

struct AppConfiguration {
    let supabaseURL: URL
    let publishableKey: String

    init?(bundle: Bundle = .main) {
        guard
            let host = bundle.object(forInfoDictionaryKey: "RuuutoSupabaseHost") as? String,
            !host.isEmpty,
            host.utf8.allSatisfy({
                (48...57).contains($0) || (65...90).contains($0)
                    || (97...122).contains($0) || $0 == 45 || $0 == 46
            }),
            let url = URL(string: "https://" + host),
            let key = bundle.object(forInfoDictionaryKey: "RuuutoSupabasePublishableKey") as? String,
            key.hasPrefix("sb_publishable_"),
            key.count > "sb_publishable_".count
        else { return nil }

        supabaseURL = url
        publishableKey = key
    }
}
