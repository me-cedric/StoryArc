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
    static func read(
        sources: [Source],
        credentials: CredentialStore?
    ) async -> [(Publication, UUID)] {
        var found: [(Publication, UUID)] = []
        for source in sources {
            let rows = await publications(of: source, credentials: credentials)
            found.append(contentsOf: rows.map { ($0, source.id) })
        }
        return found
    }

    private static func publications(
        of source: Source,
        credentials: CredentialStore?
    ) async -> [Publication] {
        switch source.kind {
        case .kavitaServer:
            guard let page = KavitaPage(source: source, credentials: credentials) else { return [] }
            let client = KavitaClient(address: page.address)
            return (try? await KavitaContributor.publications(source: source.id, client: client))
                ?? []

        case .opdsCatalog:
            guard let page = CataloguePage(source: source, credentials: credentials) else {
                return []
            }
            let feed = try? await OpdsClient(origin: page.origin).feed(at: page.url, credential: page.credential)
            return feed?.publications
                .compactMap { OpdsContributor.publication(source: source.id, entry: $0) } ?? []

        case .networkShare:
            guard let page = SmbPage(source: source, credentials: credentials) else { return [] }
            return await SmbContributor.publications(
                source: source.id,
                client: SmbClient(address: page.address),
                root: page.address.path
            )

        // Already in the library: its files are what the scan walks.
        case .localFolder: return []
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
        let found = await ServerLibrary.read(
            sources: registry.sources,
            credentials: CredentialStore()
        )
        for (publication, sourceID) in found {
            _ = adopt(publication, from: sourceID)
        }
    }
}
