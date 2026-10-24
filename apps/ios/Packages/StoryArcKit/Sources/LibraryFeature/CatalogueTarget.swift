internal import Foundation

internal import Catalogue
internal import Kavita
internal import StoryArcCore

/// What the reader pasted into "Add catalogue", once it has been recognised.
///
/// Kavita's OPDS URL is `https://host/api/opds/<key>`, and that key is the reader's own
/// full-privilege API key — the one that mints session tokens. Pasted into the generic
/// catalogue sheet it used to be treated as any other feed: the fetch succeeded because the
/// path *is* the credential, nothing ever asked for a secret, and the whole key-bearing URL
/// was written into the registry — which is `UserDefaults`, in the clear, in every backup.
/// `sources` forbids a secret reaching preferences or backups, and `kavita-server` asks for
/// such a paste to configure "a native Kavita source rather than a generic OPDS source".
/// Nothing in that sentence says which sheet it was pasted into.
///
/// Recognition is a value rather than a branch inside the connection, so what the app does
/// with an address can be asserted without a server. Android's `CatalogueTarget` answers the
/// same three ways.
enum CatalogueTarget: Equatable {
    /// A Kavita server, with the key already taken out of the address.
    case kavita(KavitaAddress)

    /// A feed to fetch.
    case feed(URL)

    /// Not an address at all.
    case unusable

    /// Kavita first, always.
    ///
    /// Order is the whole point: `OpdsDocument.address(from:)` completes a Kavita OPDS URL
    /// into a perfectly good feed URL, so anything that asks it first has already lost the
    /// key into the catalogue flow.
    static func of(_ typed: String) -> CatalogueTarget {
        if let address = KavitaAddress.fromOpds(typed) { return .kavita(address) }
        guard let url = OpdsDocument.address(from: typed) else { return .unusable }
        return .feed(url)
    }

    /// The locator a registry entry may hold for a feed.
    ///
    /// The registry is preferences, so a locator is a string the reader's backup carries in
    /// the clear. `https://user:password@host/feed` is a working credential written as an
    /// address, and `URLSession` will authenticate from it — so the caller moves it into the
    /// secure store and saves what this returns, which is the same address with the secret
    /// taken out of it. `?apikey=…` is the same case in the query: ``secretQuery(of:)`` goes
    /// to the secure store, and ``ExportableAddress`` removes it here.
    static func storableLocator(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user != nil || components.password != nil
        else { return ExportableAddress.withoutSecret(url.absoluteString) }
        components.user = nil
        components.password = nil
        return ExportableAddress.withoutSecret(components.url?.absoluteString ?? url.absoluteString)
    }

    /// The query items of `url` that name a secret, as typed, or nil when there is none.
    static func secretQuery(of url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery?
            .split(separator: "&") ?? []
        let secret = items.filter { item in
            let name = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            return ExportableAddress.secretNames.contains(name.lowercased())
        }
        return secret.isEmpty ? nil : secret.joined(separator: "&")
    }

    /// The stored `locator` with the ``secretQuery(of:)`` put back, for the request only.
    static func withQuery(_ locator: String, query: String?) -> String {
        guard let query else { return locator }
        let hash = locator.firstIndex(of: "#") ?? locator.endIndex
        let head = String(locator[..<hash])
        return head + (head.contains("?") ? "&" : "?") + query + String(locator[hash...])
    }
}
