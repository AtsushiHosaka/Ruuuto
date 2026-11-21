import Foundation

struct AppConfiguration {
    let supabaseURL: URL
    let publishableKey: String
    let invitationOrigin: URL?

    init?(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let environmentURL = environment["RUUUTO_SUPABASE_URL"]
        let environmentKey = environment["RUUUTO_SUPABASE_PUBLISHABLE_KEY"]
        let usesEnvironment = environmentURL != nil || environmentKey != nil

        let projectURL = usesEnvironment
            ? environmentURL
            : Self.bundleURL(for: "RuuutoSupabaseHost", in: bundle)
        let key = usesEnvironment
            ? environmentKey
            : bundle.object(forInfoDictionaryKey: "RuuutoSupabasePublishableKey") as? String

        guard let url = Self.httpsOrigin(projectURL),
              let key, key.hasPrefix("sb_publishable_"),
              key.count > "sb_publishable_".count,
              key.utf8.allSatisfy({ Self.isASCIIAlphanumeric($0) || $0 == 45 || $0 == 95 })
        else { return nil }

        supabaseURL = url
        publishableKey = key
        invitationOrigin = Self.httpsOrigin(
            environment["RUUUTO_INVITATION_URL"] ?? Self.bundleURL(for: "RuuutoInvitationHost", in: bundle)
        )
    }

    private static func bundleURL(for key: String, in bundle: Bundle) -> String? {
        guard let host = bundle.object(forInfoDictionaryKey: key) as? String,
              !host.isEmpty else { return nil }
        return "https://" + host
    }

    private static func httpsOrigin(_ value: String?) -> URL? {
        guard let value, var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), host.contains("."),
              components.percentEncodedHost?.lowercased() == host,
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.query == nil, components.fragment == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/"
        else { return nil }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            (1...63).contains(label.utf8.count)
                && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { isASCIIAlphanumeric($0) || $0 == 45 }
        }) else { return nil }

        components.scheme = "https"
        components.host = host
        components.port = nil
        components.path = ""
        return components.url
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }
}
