internal import Foundation

internal import Catalogue
internal import Kavita
internal import Persistence
internal import StoryArcCore

/// Putting one question to a configured library that lives somewhere else.
///
/// Each kind of library is asked in its own dialect and answers in the one shape the merge
/// understands. Nothing here decides *when* to ask or *what to do* with a failure — that is
/// ``LibrarySearch``'s job, and keeping the two apart is what lets the interesting rule (a
/// late answer never moves a row) be tested without a network.
///
/// Android's `RemoteSearch` asks the same two kinds the same two ways.
enum RemoteSearch {

    /// Whether this library can be asked a question at all.
    ///
    /// A folder cannot: its contents are already in the local index, so asking it would be
    /// asking the device about itself. A network share cannot either — SMB has no search,
    /// and walking a whole share per keystroke is not a search, it is an outage.
    static func answers(_ source: Source) -> Bool {
        switch source.kind {
        case .kavitaServer, .opdsCatalog: true
        case .localFolder, .networkShare: false
        }
    }

    /// What this library says about the term.
    ///
    /// Throws when it cannot say anything, which is the case the caller turns into the
    /// quiet "could not answer" notice. It never returns an empty list *instead* of
    /// throwing: a server that answered "nothing" and a server that did not answer are
    /// different facts, and a reader deciding whether to keep waiting needs them kept apart.
    @MainActor
    static func rows(
        from source: Source,
        term: String,
        credentials: CredentialStore,
        pins: CertificatePins
    ) async throws -> [SearchResult] {
        if let page = KavitaPage(source: source, credentials: credentials) {
            return kavitaRows(try await KavitaClient(address: page.address).find(term), from: page.id)
        }
        if let page = CataloguePage(source: source, credentials: credentials) {
            return catalogueRows(try await entries(matching: term, in: page, pins: pins), from: source)
        }
        // No page could be built, which means the secret this library needs is not in the
        // keychain any more. Indistinguishable from being away, as far as a search goes.
        throw SearchUnanswered()
    }

    /// A library that had nothing to say and no way to say why.
    struct SearchUnanswered: Error {}

    /// What a Kavita server matched, as rows.
    ///
    /// A person and a subject carry no route because Kavita answers them with a name alone —
    /// there is nowhere for the row to go, and ``SearchResult/isOpenable`` is how the list
    /// knows not to pretend otherwise.
    static func kavitaRows(_ hits: [KavitaHit], from sourceID: String) -> [SearchResult] {
        hits.map { hit in
            SearchResult(
                kind: kind(of: hit.kind),
                title: hit.title,
                route: hit.isOpenable
                    ? SearchRoute(sourceID: sourceID, key: String(hit.seriesId))
                    : nil
            )
        }
    }

    /// Which heading a Kavita match belongs under.
    ///
    /// A chapter is a publication: it is the thing a reader opens and reads, whatever the
    /// server calls it. The mapping is here rather than on `KavitaHit` because it is a fact
    /// about *this* screen's four headings, not about Kavita.
    static func kind(of hit: KavitaHit.Kind) -> MatchKind {
        switch hit {
        case .series: .series
        case .chapter: .publication
        case .person: .person
        case .subject: .tag
        }
    }

    /// What a catalogue matched, as rows.
    static func catalogueRows(_ entries: [OpdsEntry], from source: Source) -> [SearchResult] {
        entries.map { entry in
            SearchResult(
                kind: .publication,
                title: entry.title,
                detail: entry.series ?? entry.authors.first,
                route: SearchRoute(sourceID: source.id.uuidString, key: entry.id)
            )
        }
    }

    /// The entries a catalogue offers for this term.
    ///
    /// Two requests in the worst case, and only because OPDS is built that way: the root
    /// feed is what says whether the server can search at all, and where. A catalogue that
    /// cannot search falls back to filtering the feed it just fetched, which is what
    /// `opds-catalog` already asks of the browser — the same answer, reached without the
    /// reader having to walk in first.
    @MainActor
    private static func entries(
        matching term: String,
        in page: CataloguePage,
        pins: CertificatePins
    ) async throws -> [OpdsEntry] {
        let root = CatalogueBrowser(
            title: page.title,
            url: page.url,
            credential: page.credential,
            pins: pins,
            origin: page.origin
        )
        await root.load()
        guard root.state == .ready else { throw SearchUnanswered() }

        switch await root.search(term) {
        case let .local(found):
            return found
        case .cleared:
            return []
        case let .server(url):
            let results = CatalogueBrowser(
                title: page.title,
                url: url,
                credential: page.credential,
                pins: pins,
                // The origin the reader saved, not the one the feed named: a search address
                // chosen by the server is not a licence to send the reader's credential
                // somewhere else.
                origin: page.origin
            )
            await results.load()
            guard results.state == .ready else { throw SearchUnanswered() }
            return results.searchable
        }
    }
}
