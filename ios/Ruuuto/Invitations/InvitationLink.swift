import Foundation

struct InvitationLink: Equatable, Identifiable, Sendable {
    let url: URL
    let token: String

    var id: String { token }

    init?(url: URL, allowedOrigin: URL, pathPrefix: String) {
        guard
            let incoming = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let origin = URLComponents(url: allowedOrigin, resolvingAgainstBaseURL: false),
            incoming.scheme?.lowercased() == "https",
            origin.scheme?.lowercased() == "https",
            let host = origin.host?.lowercased(),
            incoming.host?.lowercased() == host,
            (incoming.port ?? 443) == (origin.port ?? 443),
            incoming.user == nil, incoming.password == nil,
            incoming.query == nil, incoming.fragment == nil
        else { return nil }

        let prefix = pathPrefix.split(separator: "/")
        let path = incoming.percentEncodedPath.split(separator: "/")
        guard !prefix.isEmpty, path.count == prefix.count + 1, path.dropLast().elementsEqual(prefix),
              let token = path.last?.removingPercentEncoding,
              (1...512).contains(token.utf8.count),
              token.utf8.allSatisfy({
                  (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                      || $0 == 45 || $0 == 46 || $0 == 95
              })
        else { return nil }

        self.url = url
        self.token = token
    }
}
