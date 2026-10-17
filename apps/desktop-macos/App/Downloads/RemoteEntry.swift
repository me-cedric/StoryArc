import Catalogue
import Foundation
import LibraryFeature
import Persistence
import StoryArcCore

/// The catalogue entry behind a library row from an OPDS source, found again so the row can
/// be downloaded.
///
/// A Mac copy of `RemoteMemberResolution` (internal to `LibraryFeature`): a row keeps the
/// entry's id as `opds:<entry>` in its server identity, and the queue needs the entry and its
/// acquisition. The source's feed is read again, following `next` for a few pages, because a
/// row may come from any page the library read. Making the package's resolver public is a
/// parent edit under `apps/ios`; until then this is the Mac's.
enum RemoteEntry {
    static let prefix = "opds:"
    static let pageLimit = 10

    /// The entry id a row names, or `nil` for a row that is not from a catalogue.
    static func entryID(of publication: Publication) -> String? {
        guard let remote = publication.identity.serverIdentifier?.remoteID, remote.hasPrefix(prefix) else { return nil }
        return String(remote.dropFirst(prefix.count))
    }

    /// Whether this row can be downloaded through the queue: it came from a catalogue.
    static func isDownloadable(_ publication: Publication, in registry: SourceRegistry) -> Bool {
        guard entryID(of: publication) != nil, let sourceID = publication.identity.serverIdentifier?.sourceID else {
            return false
        }
        return registry[sourceID]?.kind == .opdsCatalog
    }

    /// What the queue needs to download a row.
    struct Resolved: Sendable {
        let entry: OpdsEntry
        let acquisition: OpdsAcquisition
        let sourceID: UUID
    }

    /// The entry and the best acquisition, read from the row's own source.
    static func resolve(
        _ publication: Publication, in registry: SourceRegistry, credentials: CredentialStore
    ) async -> Resolved? {
        guard let entryID = entryID(of: publication),
              let sourceID = publication.identity.serverIdentifier?.sourceID,
              let source = registry[sourceID],
              let page = CataloguePage(source: source, credentials: credentials)
        else { return nil }
        let client = OpdsClient(pins: .app, origin: page.origin)
        var next: URL? = page.url
        for _ in 0..<pageLimit {
            guard let url = next, let feed = try? await client.feed(at: url, credential: page.credential) else { break }
            let entries = feed.publications + feed.groups.flatMap(\.publications)
            if let entry = entries.first(where: { $0.id == entryID }),
               let acquisition = CatalogueAcquisition.best(of: entry) {
                return Resolved(entry: entry, acquisition: acquisition, sourceID: sourceID)
            }
            next = feed.next
        }
        return nil
    }
}
