public import Foundation
public import Catalogue
public import Persistence
public import StoryArcCore

/// One page of a catalogue, and how to reach the next.
///
/// `opds-catalog`'s second requirement: navigation feeds are "browsable sections" and
/// acquisition feeds are "publication grids", following facets and pagination. A page is
/// one of these; entering a section makes another.
@Observable
@MainActor
public final class CatalogueBrowser {
    /// What the page is doing.
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var state: State = .idle

    /// The feed as it arrived, for its title, sections and facets.
    public private(set) var feed: OpdsFeed?

    /// Publications from this page and every page followed after it.
    ///
    /// Accumulated rather than replaced: `opds-catalog` forbids a visible "load more", so
    /// the second page has to arrive underneath the first without the grid resetting.
    public private(set) var entries: [OpdsEntry] = []

    /// Whether another page exists. Read by the grid as it nears the end.
    public var hasMore: Bool { next != nil }

    /// Everything on this page a local search can look through.
    ///
    /// The grid *and* every group: an OPDS 2.0 feed can put its whole catalogue in named
    /// groups and leave the top level empty, and a search that only looked at ``entries``
    /// would answer "nothing" for a page full of publications.
    public var searchable: [OpdsEntry] {
        entries + (feed?.groups.flatMap(\.publications) ?? [])
    }

    public let title: String
    public let credential: OpdsCredential?

    /// Where the source the reader configured lives.
    ///
    /// Carried down every section, facet and search rather than re-derived from the page in
    /// hand: a section's address is chosen by the server, and an origin taken from it would
    /// be the attacker's answer to the question it was asked to settle.
    public let origin: OpdsOrigin?

    /// Shared with the cells, which fetch covers through the same credential.
    let client: OpdsClient

    /// Carried so a section of this catalogue inherits the reader's trust decisions.
    public let pins: CertificatePins
    private let root: URL
    private var next: URL?

    /// A page already being fetched, so a fast scroll asks once.
    private var loadingMore = false

    public init(
        title: String,
        url: URL,
        credential: OpdsCredential?,
        pins: CertificatePins = CertificatePins(),
        /// Nil at the top of a catalogue, where the address is the one the reader saved and
        /// is therefore its own origin. Passed explicitly from there down.
        origin: OpdsOrigin? = nil
    ) {
        self.title = title
        root = url
        self.credential = credential
        self.pins = pins
        self.origin = origin ?? OpdsOrigin(url: url)
        client = OpdsClient(pins: pins, origin: self.origin)
    }

    /// Fetches the first page. Safe to call again; it does nothing once loaded.
    public func load() async {
        guard state == .idle else { return }
        await fetch(root, appending: false)
    }

    /// Fetches again from the top, discarding what was shown.
    public func reload() async {
        state = .idle
        entries = []
        next = nil
        await load()
    }

    /// Fetches the next page, if the reader has scrolled near enough to want it.
    ///
    /// Asked per row rather than by a button, per the spec. The threshold is most of a
    /// screenful: asking at the very last row means the reader waits, and asking at the
    /// first means the whole catalogue arrives whether or not anyone scrolls.
    public func loadMore(after entry: OpdsEntry) async {
        guard let next, !loadingMore,
              let position = entries.firstIndex(where: { $0.id == entry.id }),
              position >= entries.count - Self.prefetchRows
        else { return }
        loadingMore = true
        await fetch(next, appending: true)
        loadingMore = false
    }

    private static let prefetchRows = 6

    /// What a search can do here.
    public enum SearchOutcome: Equatable, Sendable {
        /// The server will answer, at this address, in a page of its own.
        case server(URL)

        /// This catalogue does not advertise search, so what is loaded was filtered.
        case local([OpdsEntry])

        /// The term was empty.
        case cleared
    }

    /// Searches the server when it advertises search, and says so when it cannot.
    ///
    /// `opds-catalog`: "a catalogue without search falls back to filtering the cached
    /// catalogue, and says so". The fallback filters what has been fetched, which is the
    /// only cache there is until downloads exist.
    public func search(_ term: String) -> SearchOutcome {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .cleared }
        guard let url = searchURL(for: trimmed) else {
            return .local(searchable.filter { $0.matches(trimmed) })
        }
        return .server(url)
    }

    /// Where a search for this term goes, when the catalogue advertises one.
    public func searchURL(for term: String) -> URL? {
        guard let template = feed?.searchTemplate else { return nil }
        return Self.fill(template, with: term.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Substitutes a term into whichever placeholder the template uses.
    ///
    /// OpenSearch says `{searchTerms}`; OPDS 2.0 templates in the wild say `{query}`,
    /// `{?query}` or `{q}`. They mean the same thing, and a reader whose server picked the
    /// other spelling should not find search silently broken.
    static func fill(_ template: String, with term: String) -> URL? {
        let escaped = term.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? term
        var filled = template
        for placeholder in ["{searchTerms}", "{?query}", "{query}", "{?q}", "{q}"] {
            filled = filled.replacingOccurrences(of: placeholder, with: escaped)
        }
        // A template nothing was substituted into would fetch the unfiltered feed and look
        // like a search that matched everything.
        guard filled != template else { return nil }
        return URL(string: filled)
    }

    private func fetch(_ url: URL, appending: Bool) async {
        if !appending { state = .loading }
        do {
            let page = try await client.feed(at: url, credential: credential)
            if appending {
                // Matched on identifier: a server that repeats an entry across a page
                // boundary is common when the underlying list changed mid-scroll.
                let known = Set(entries.map(\.id))
                entries += page.publications.filter { !known.contains($0.id) }
            } else {
                feed = page
                entries = page.publications
            }
            next = page.next
            state = .ready
        } catch let refusal as OpdsRefusal {
            // A certificate refused here rather than while adding the catalogue means the
            // server's certificate changed since the reader pinned it, which is the case
            // pinning exists to catch.
            if case let .untrusted(certificate) = refusal {
                state = .failed(
                    String(
                        format: String(
                            localized: "catalogue.error.changedCertificate",
                            bundle: .module
                        ),
                        certificate.host
                    )
                )
            }
        } catch let error as OpdsError {
            state = .failed(CatalogueMessages.describe(error))
        } catch {
            state = .failed(CatalogueMessages.reachability(error))
        }
    }
}

extension OpdsEntry {
    /// Whether a locally filtered search should keep this entry.
    func matches(_ term: String) -> Bool {
        let needle = term.lowercased()
        return title.lowercased().contains(needle)
            || authors.contains { $0.lowercased().contains(needle) }
            || (series?.lowercased().contains(needle) ?? false)
    }
}

/// What is needed to open a saved catalogue: an address, a name, and a secret.
///
/// Values, so the view that shows the page can build the browser itself. Reading the
/// keychain is the only part that is not free, and it happens once per push.
public struct CataloguePage: Sendable {
    public let title: String
    public let url: URL
    public let credential: OpdsCredential?

    /// The origin the credential belongs to: this address, and nowhere the feed names.
    public let origin: OpdsOrigin?

    /// Nil when the source is not a catalogue or has no address, which is what stops a
    /// folder from being opened as one.
    public init?(source: Source, credentials: CredentialStore?) {
        guard source.kind == .opdsCatalog,
              let locator = source.locator,
              let url = URL(string: locator)
        else { return nil }

        title = source.displayName
        self.url = url
        origin = OpdsOrigin(url: url)
        credential = source.credentialReference
            .flatMap { credentials?.secret(for: $0) }
            .flatMap(OpdsCredential.init(stored:))
    }
}
