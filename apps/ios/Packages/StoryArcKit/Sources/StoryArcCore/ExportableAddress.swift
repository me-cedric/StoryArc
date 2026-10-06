public import Foundation

/// A source's address with everything that could unlock it taken out, and nothing else.
///
/// `library-portability` / *A server in the export*: "its address, its name, its username and
/// its settings travel, and its secret does not". A ``Source/locator`` is the address, and an
/// address is one of the few places in this app where a secret can sit in plain sight — a
/// share mounted as `smb://reader:hunter2@nas.local/comics`, a catalogue subscribed to as
/// `https://opds.example/feed?apikey=…`. `AGENTS.md` non-negotiable 4 names backups, and an
/// export is a backup.
///
/// **Deliberately not ``DiagnosticRedaction``.** That function removes the hostname too,
/// because a diagnostic is a file the reader sends to somebody else and a hostname is
/// something they would not knowingly publish. An export is a file the reader carries to
/// their own next device, and a source whose hostname has been removed is a source that
/// cannot be reached — the export's whole purpose. The two over-redact and under-redact in
/// opposite directions on purpose, and the spec says so in as many words.
///
/// Android's `ExportableAddress` applies the same two rules in the same order.
public enum ExportableAddress {

    /// The address, with the password out of its userinfo and any secret-named query
    /// parameter dropped.
    ///
    /// A locator this app does not recognise as a URL — a folder path, a bookmark name — is
    /// returned as it stands. There is nowhere in a path for a secret to hide, and mangling
    /// one would lose the source.
    public static func withoutSecret(_ locator: String) -> String {
        withoutSecretQueryItems(withoutPassword(locator))
    }

    /// `smb://reader:hunter2@nas.local/comics` becomes `smb://reader@nas.local/comics`.
    ///
    /// The user survives because `library-portability` says the username travels; a reader
    /// signing in again on the new device should have to supply the secret and not also
    /// remember which account it was.
    private static func withoutPassword(_ locator: String) -> String {
        locator.replacing(#/([a-zA-Z][a-zA-Z0-9+.\-]*:\/\/)([^\/\s?#@]*)@/#) { match in
            let user = match.output.2.split(separator: ":", maxSplits: 1).first ?? ""
            return "\(match.output.1)\(user)@"
        }
    }

    /// Drops `?apikey=…`, `?token=…` and their kin, and keeps every other parameter.
    ///
    /// The same vocabulary ``DiagnosticRedaction`` uses for rule 3, because a word that means
    /// "secret" means it in both files. Dropped rather than blanked: a parameter whose value
    /// is `[redacted]` would be sent to the server verbatim on the next launch, and a server
    /// answering 401 to a literal `[redacted]` is a worse failure to explain than a parameter
    /// that is simply not there.
    private static func withoutSecretQueryItems(_ locator: String) -> String {
        // The fragment is cut first and filtered by the same rule. A fragment never reaches
        // a server, so it reads as harmless, but it is still text in an exported file — and
        // `https://host/feed#token=abc` carries the whole token past a filter that only ever
        // looks after a `?`.
        var beforeHash = locator
        var fragment: String?
        if let hash = locator.firstIndex(of: "#") {
            beforeHash = String(locator[locator.startIndex..<hash])
            fragment = keptItems(String(locator[locator.index(after: hash)...]))
        }

        var address = beforeHash
        var query: String?
        if let separator = beforeHash.firstIndex(of: "?") {
            address = String(beforeHash[beforeHash.startIndex..<separator])
            query = keptItems(String(beforeHash[beforeHash.index(after: separator)...]))
        }

        return address
            + (query.map { "?\($0)" } ?? "")
            + (fragment.map { "#\($0)" } ?? "")
    }

    /// The `a=1&b=2` items that name no secret, or nil where none is left.
    private static func keptItems(_ items: String) -> String? {
        let kept = items.split(separator: "&", omittingEmptySubsequences: false).filter { item in
            let name = item.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
            return !secretNames.contains(name.lowercased())
        }
        return kept.isEmpty ? nil : kept.joined(separator: "&")
    }

    /// The parameter names that introduce a secret.
    ///
    /// A list rather than a shape test, because a parameter's *value* is opaque by
    /// definition and only its name says what it is. Kept in step with
    /// ``DiagnosticRedaction``'s rule 3 by `ExportableAddressTests`, which asserts both
    /// functions against the same words.
    static let secretNames: Set<String> = [
        "token", "password", "passwd", "pwd", "secret", "key", "apikey", "api_key", "api-key",
        "x-api-key", "auth", "authorization", "bearer", "accesstoken", "access_token",
        "refresh_token", "refreshtoken", "session", "sessionid", "session_id", "sid",
        "credential", "credentials", "signature", "sig",
    ]
}
