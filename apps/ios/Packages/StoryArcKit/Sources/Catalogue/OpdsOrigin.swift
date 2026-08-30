public import Foundation

/// Where a configured source lives: scheme, host and port, and nothing else.
///
/// A catalogue chooses every address the app fetches after the first one — the covers, the
/// next page, the acquisition link. `sources` promises that "data leaves the device only to
/// the sources the user configured", and an `Authorization` header is data. So the origin
/// the reader configured travels beside the credential, and this type is what decides
/// whether the address in front of it is that origin or somebody else's.
///
/// Scheme, host and port together, because any one of them alone is not an origin: a
/// credential that followed `https://books.example` to `http://books.example` has gone out
/// in the clear, and one that followed it to port 8443 has gone to a different server.
///
/// Android's `OpdsOrigin` is the same type.
public struct OpdsOrigin: Sendable, Equatable {
    public let scheme: String
    public let host: String
    public let port: Int

    /// Nil for anything that is not a web address, which is what stops a `file:` or `ftp:`
    /// href out of a feed from being treated as a place a credential could belong to.
    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), Self.web.contains(scheme),
              let host = url.host()?.lowercased(), !host.isEmpty
        else { return nil }
        self.scheme = scheme
        self.host = host
        // The scheme's own default when none is written, so `https://a` and `https://a:443`
        // are one origin rather than two.
        port = url.port ?? (scheme == "https" ? 443 : 80)
    }

    /// The only two schemes this app fetches over.
    private static let web: Set<String> = ["http", "https"]

    /// Whether an address is one the app will fetch at all.
    ///
    /// Judged before anything opens a connection. On Android `URL.openConnection()` accepts
    /// `file:` and `ftp:` and hands back a connection that is not an `HttpURLConnection`;
    /// on iOS the request simply fails, later and less clearly. Both want the same answer
    /// here.
    public static func isFetchable(_ url: URL) -> Bool {
        url.scheme.map { web.contains($0.lowercased()) } ?? false
    }

    /// Whether the credential for this origin may travel to this address.
    public func admits(_ url: URL) -> Bool {
        OpdsOrigin(url: url) == self
    }

    /// Whether following this address would step down from `https` to cleartext.
    ///
    /// A reader who typed `http://nas.local` meant it and is not downgraded by anything.
    /// A reader who typed `https://` and is then sent to `http://` by the feed is being
    /// moved somewhere they did not choose, whether by a broken proxy or a hostile one.
    public func downgrades(_ url: URL) -> Bool {
        scheme == "https" && url.scheme?.lowercased() == "http"
    }
}

/// What to do with a redirect the server chose.
///
/// `URLSession` follows redirects on its own and carries every header across, so a 302 to
/// another host is the same credential leak as an absolute href to one — with nothing in
/// the feed to see. This is the hook both sessions in the app install.
enum OpdsRedirect {
    /// The request to follow, or nil to stop.
    ///
    /// The origin compared against is the *first* request's, not the previous hop's:
    /// recomputing it each time would let a chain of two redirects arrive anywhere with the
    /// header intact.
    static func following(_ request: URLRequest, from original: URLRequest?) -> URLRequest? {
        guard let url = request.url, OpdsOrigin.isFetchable(url) else { return nil }
        guard let started = original?.url, let origin = OpdsOrigin(url: started) else {
            return request
        }
        if origin.downgrades(url) { return nil }
        guard origin.admits(url) else {
            var anonymous = request
            anonymous.setValue(nil, forHTTPHeaderField: "Authorization")
            return anonymous
        }
        return request
    }
}
