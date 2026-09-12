import Foundation

internal import Kavita
internal import Persistence
internal import StoryArcCore

// A server's shelves, and the one round of requests that finds them.
//
// Split from `KavitaShelfViews.swift` on 2026-09-12, when that file crossed the 400-line cap
// that `scripts/line-cap.mjs` holds. `AGENTS.md` asks for a split rather than a waiver, and
// this is the seam the file already had: a model and its loader above, two views below. They
// have no SwiftUI between them.

/// One of a server's own shelves.
///
/// A collection and a reading list differ in kind — one groups series with no order, the
/// other is an ordered run of chapters — so the flag chooses the screen rather than one
/// screen guessing from what it finds.
public struct ServerShelf: Identifiable, Sendable {
    public let server: KavitaPage
    public let id: Int
    public let title: String
    public let isList: Bool
    /// Whether a reader chose this shelf's cover on the server.
    ///
    /// `collections-and-reading-lists` composites the first four members "unless the user
    /// sets a specific one", and Kavita's `coverImageLocked` is the server's word for having
    /// set one. False — including for every server too old to send the field — composites.
    public var chosenCover: Bool = false

    /// Every Kavita server's shelves, asked for once.
    static func all(
        in registry: SourceRegistry,
        credentials: CredentialStore?
    ) async -> [ServerShelf] {
        await fetch(in: registry, credentials: credentials).shelves
    }

    /// The shelves, and the servers that could be asked for them at all.
    ///
    /// Both come out of the same round of requests because they are the same question asked
    /// once. Keeping them apart matters: a server with no reading lists yet still *supports*
    /// them, and one that did not answer does not — a distinction an empty array cannot make,
    /// and the one `collections-and-reading-lists` needs before it offers to copy a list.
    static func fetch(
        in registry: SourceRegistry,
        credentials: CredentialStore?
    ) async -> ServerShelves {
        var found: [ServerShelf] = []
        var listCapable: [KavitaPage] = []
        var collectionCapable: [KavitaPage] = []
        for source in registry.sources {
            guard let page = KavitaPage(source: source, credentials: credentials) else { continue }
            let client = KavitaClient(address: page.address)
            // Asked and answered on its own. A server can answer one of these and not the
            // other, so a refused collections request must not cost the reader that server's
            // reading lists as well.
            if let collections = try? await client.collections() {
                collectionCapable.append(page)
                found += collections.map {
                    // A collection carries the same locked-cover flag a reading list does.
                    ServerShelf(
                        server: page,
                        id: $0.id,
                        title: $0.title,
                        isList: false,
                        chosenCover: $0.coverImageLocked
                    )
                }
            }
            // Answered rather than non-empty: a server that has no lists yet is exactly the
            // one a reader is most likely to want to copy their first list onto.
            if let lists = try? await client.readingLists() {
                listCapable.append(page)
                found += lists.map {
                    ServerShelf(
                        server: page,
                        id: $0.id,
                        title: $0.title,
                        isList: true,
                        chosenCover: $0.coverImageLocked
                    )
                }
            }
        }
        return ServerShelves(
            shelves: found,
            listCapable: listCapable,
            collectionCapable: collectionCapable
        )
    }
}

/// What one round of asking every server produced.
struct ServerShelves: Sendable {
    let shelves: [ServerShelf]

    /// The servers that answered when asked for their reading lists — reachable, and able to
    /// hold one. A server that did not answer is simply not offered.
    let listCapable: [KavitaPage]

    /// The same question about collections, kept apart from the answer about lists because
    /// they are two different capabilities and a server can answer one and not the other.
    var collectionCapable: [KavitaPage] = []
}
