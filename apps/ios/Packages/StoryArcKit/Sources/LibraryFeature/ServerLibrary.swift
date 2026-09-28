import Catalogue
import Foundation
import Kavita
import Persistence
import Smb
import StoryArcCore

/// What the configured servers put in the library.
///
/// `library-browsing` requires one library over every source — "publications from every
/// configured source are shown together". A folder walk cannot reach a server, so this is
/// the other half of the answer.
///
/// **Nothing here ever removes a row.** Reconciliation deletes only from a source whose own
/// round covered it, and a server is in no round, so a server that refuses or answers
/// nothing costs a reader nothing. `sources`: "a failed refresh and an emptied source are
/// different things." Android's `ServerLibrary` is its twin.
enum ServerLibrary {

    /// Every server's slice, with the source each row came through.
    ///
    /// Per source, so one slow server does not hold up another. A source that throws
    /// contributes nothing and costs nothing.
    /// Every server's rows, and which sources held back more than they gave.
    struct Reading {
        var rows: [(Publication, UUID)] = []
        /// Sources whose read stopped at its own limit. ``SourceSlice`` explains that, and
        /// the source screen is what says it out loud.
        var partial: Set<UUID> = []
    }

    static func read(
        sources: [Source],
        credentials: CredentialStore?
    ) async -> Reading {
        var reading = Reading()
        for source in sources {
            let slice = await publications(of: source, credentials: credentials)
            reading.rows.append(contentsOf: slice.publications.map { ($0, source.id) })
            if slice.holdsMore { reading.partial.insert(source.id) }
        }
        return reading
    }

    private static func publications(
        of source: Source,
        credentials: CredentialStore?
    ) async -> SourceSlice {
        switch source.kind {
        case .kavitaServer:
            guard let page = KavitaPage(source: source, credentials: credentials) else { return .none }
            let client = KavitaClient(address: page.address)
            return (try? await KavitaContributor.publications(source: source.id, client: client))
                ?? .none

        case .opdsCatalog:
            guard let page = CataloguePage(source: source, credentials: credentials) else {
                return .none
            }
            let feed = try? await OpdsClient(origin: page.origin).feed(at: page.url, credential: page.credential)
            guard let feed else { return .none }
            // The feed says so itself. A `next` link is the catalogue's own statement that
            // this page is not the whole of it.
            return SourceSlice(
                publications: feed.publications
                    .compactMap { OpdsContributor.publication(source: source.id, entry: $0) },
                holdsMore: feed.next != nil
            )

        case .networkShare:
            guard let page = SmbPage(source: source, credentials: credentials) else { return .none }
            return await SmbContributor.publications(
                source: source.id,
                client: SmbClient(address: page.address),
                root: page.address.path
            )

        // Already in the library: its files are what the scan walks.
        case .localFolder: return .none
        }
    }
}

extension LibraryModel {
    /// Every configured server's publications, adopted as a scanned file is.
    ///
    /// Adopted through the same `adopt(_:from:)` a walk uses, so a server's row and a
    /// folder's row are one kind of thing: same precedence, same identity, same grid.
    ///
    /// Here rather than in `LibraryScanning` because that file is at its 400-line cap, and
    /// this is where the reading it drives already lives.
    public func readServers() async {
        let reading = await ServerLibrary.read(
            sources: registry.sources,
            credentials: CredentialStore()
        )
        // A source already mid-continuation keeps its progress: a pull-to-refresh reads
        // page one again, and page one alone knows nothing past its own first slice —
        // replacing an entry already at page nine with a fresh "page two" would be the
        // continuation rewinding itself every time the reader pulls down.
        for sourceID in reading.partial where partialSources[sourceID] == nil {
            // Exact, not a guess: a page that reported `holdsMore` asked for at most its
            // kind's own limit and got a full page back, by ``SourceSlice``'s own rule.
            let firstSliceRead: Int
            switch registry.sources.first(where: { $0.id == sourceID })?.kind {
            case .kavitaServer: firstSliceRead = KavitaContributor.firstSlice
            case .networkShare: firstSliceRead = SmbContributor.firstSlice
            // A catalogue's first slice is one feed page, whatever size the server chose —
            // nothing here names that number, and nothing yet continues an OPDS read past
            // it, so there is no total to divide it into either.
            case .opdsCatalog, .localFolder, nil: firstSliceRead = 0
            }
            partialSources[sourceID] = .started(firstSliceRead: firstSliceRead)
        }
        for sourceID in partialSources.keys where !reading.partial.contains(sourceID) {
            partialSources.removeValue(forKey: sourceID)
        }
        for (publication, sourceID) in reading.rows {
            _ = adopt(publication, from: sourceID)
        }
        continueReadingServers()
        guard !reading.rows.isEmpty else { return }
        // And written down, which nothing did: the snapshot was written when a *folder*
        // walk finished, so a reader whose library is one server and no folders had nothing
        // cached and opened the app offline to an empty shelf. A server's row has no file
        // behind it, so this is the only thing that carries it across a launch.
        //
        // It does not claim the shelf is fresh. This runs beside the folder walk, not
        // after it, so clearing the indicator here would answer for a walk that may still
        // be going — and one that met an unreadable directory has refreshed nothing.
        cacheLibrary(claimsFreshness: false)
    }

    /// Starts one background reader per Kavita source that is still partial.
    ///
    /// `sources`' *More from a source than the library holds*: the first slice is what
    /// ``readServers()`` above already reads; this is the rest of it, page by page, so the
    /// first screen paints from the slice and the library keeps growing underneath it
    /// rather than the reader waiting on a server with forty thousand series.
    ///
    /// SMB and OPDS are not here yet — `docs/delivery` names both as still to build.
    func continueReadingServers() {
        for source in registry.sources where source.kind == .kavitaServer {
            guard partialSources[source.id] != nil else { continue }
            guard let page = KavitaPage(source: source, credentials: CredentialStore()) else { continue }
            Task { await continueReadingKavita(source: source, client: KavitaClient(address: page.address)) }
        }
    }

    /// Reads one Kavita source's continuation until it finishes or a page refuses.
    ///
    /// **Stops and resumes cleanly when the source becomes unreachable.** A page that
    /// throws returns without touching ``partialSources``, so the very next call — another
    /// ``continueReadingServers()``, most often from the next ``readServers()`` — asks for
    /// the same page again rather than skipping it or losing the source's place.
    private func continueReadingKavita(source: Source, client: KavitaClient) async {
        // Learned once and kept beside the read count for as long as the source stays
        // partial: an unfiltered listing is proven to answer the server's whole series list
        // in one request (see `KavitaClient.series`), so this costs one request for a
        // number the reader would otherwise never see until the read finished.
        if partialSources[source.id]?.total == nil, let all = try? await client.series() {
            partialSources[source.id]?.total = all.count
        }
        while let progress = partialSources[source.id] {
            guard let result = try? await KavitaContributor.page(
                source: source.id,
                client: client,
                page: progress.nextPage
            ) else { return }
            let step = progress.advancing(
                pageRequested: progress.nextPage,
                unitsRead: result.seriesRead,
                holdsMore: result.slice.holdsMore
            )
            switch step {
            case .stale:
                return
            case .continuing(let next):
                for publication in result.slice.publications { _ = adopt(publication, from: source.id) }
                partialSources[source.id] = next
                cacheLibrary(claimsFreshness: false)
            case .finished:
                for publication in result.slice.publications { _ = adopt(publication, from: source.id) }
                partialSources.removeValue(forKey: source.id)
                cacheLibrary(claimsFreshness: false)
                return
            }
        }
    }
}
