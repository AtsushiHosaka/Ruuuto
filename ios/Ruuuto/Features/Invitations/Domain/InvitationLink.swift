import Foundation

struct InvitationLink: Equatable, Identifiable, Sendable {
    static let pathPrefix = "invite"

    let url: URL
    let token: String

    var id: String { token }

    init?(token: String, origin: URL) {
        guard Self.isAllowedToken(token),
              let origin = Self.allowedHTTPSOrigin(origin),
              var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)
        else { return nil }

        components.path = "/\(Self.pathPrefix)/\(token)"
        guard let url = components.url else { return nil }
        self.init(url: url, allowedOrigin: origin, pathPrefix: Self.pathPrefix)
    }

    init?(url: URL, allowedOrigin: URL, pathPrefix: String) {
        guard
            let incoming = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let normalizedOrigin = Self.allowedHTTPSOrigin(allowedOrigin),
            let host = normalizedOrigin.host,
            incoming.scheme?.lowercased() == "https",
            incoming.host?.lowercased() == host,
            (incoming.port ?? 443) == (normalizedOrigin.port ?? 443),
            incoming.user == nil, incoming.password == nil,
            incoming.query == nil, incoming.fragment == nil
        else { return nil }

        let prefix = pathPrefix.split(separator: "/").joined(separator: "/")
        let linkPrefix = "/\(prefix)/"
        guard !prefix.isEmpty, incoming.percentEncodedPath.hasPrefix(linkPrefix) else { return nil }

        let token = String(incoming.percentEncodedPath.dropFirst(linkPrefix.count))
        guard Self.isAllowedToken(token) else { return nil }

        self.url = url
        self.token = token
    }

    // Validate the origin syntax locally. The app link configuration establishes domain ownership.
    static func allowedHTTPSOrigin(_ url: URL?) -> URL? {
        guard let url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port == nil || components.port == 443,
              components.path.isEmpty || components.path == "/",
              let host = components.host?.lowercased(),
              isPublicHostname(host)
        else { return nil }

        components.scheme = "https"
        components.host = host
        components.port = nil
        components.path = ""
        return components.url
    }

    private static func isPublicHostname(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.utf8.count <= 253, labels.count >= 2, let suffix = labels.last,
              let suffixStart = suffix.utf8.first, (97...122).contains(suffixStart),
              !["localhost", "local", "internal", "invalid", "test", "example", "onion", "arpa"].contains(String(suffix))
        else { return false }

        return labels.allSatisfy { label in
            (1...63).contains(label.utf8.count) && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || $0 == 45 }
        }
    }

    private static func isAllowedToken(_ token: String) -> Bool {
        token != "." && token != ".." && (1...512).contains(token.utf8.count)
            && token.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                    || $0 == 45 || $0 == 46 || $0 == 95
            }
    }
}
