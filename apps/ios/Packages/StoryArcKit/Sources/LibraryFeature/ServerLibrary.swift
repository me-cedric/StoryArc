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
        partialSources = reading.partial
        for (publication, sourceID) in reading.rows {
            _ = adopt(publication, from: sourceID)
        }
        guard !reading.rows.isEmpty else { return }
        // And written down, which nothing did: the snapshot was written when a *folder*
        // walk finished, so a reader whose library is one server and no folders had nothing
        // cached and opened the app offline to an empty shelf. A server's row has no file
        // behind it, so this is the only thing that carries it across a launch.
        cacheLibrary()
    }
}
