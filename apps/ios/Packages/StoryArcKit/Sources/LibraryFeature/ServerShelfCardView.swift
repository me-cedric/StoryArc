import Kavita
import StoryArcCore
import SwiftUI

/// One of a server's own shelves, on the Shelves screen.
///
/// `collections-and-reading-lists` wants the first four *members*, and a server names its
/// members only when asked — so the card reads its own shelf once. A collection is a set of
/// series and a list is an ordered run of chapters, which is why the two ask different
/// routes and load different artwork.
///
/// Android's `ServerShelfCard` is its twin.
struct ServerShelfCardView: View {
    let shelf: ServerShelf
    var pending: Int = 0
    let model: LibraryModel

    /// The one tile a shelf has when the reader chose its cover on the server.
    static let serverCoverID = "server-cover"
    private static let serverCover = serverCoverID

    @State private var tiles: [String] = []

    var body: some View {
        ShelfCard(
            model: model,
            title: shelf.title,
            subtitle: shelf.server.title,
            tiles: tiles,
            pending: pending,
            cover: AnyView(
                ServerShelfCover(
                    tiles: shelf.chosenCover ? [Self.serverCover] : tiles,
                    load: load
                )
            )
        )
        .task(id: shelf.id) { await readMembers() }
    }

    /// `coverImageLocked` is the spec's "unless the user sets a specific one".
    private func load(_ id: String) async throws -> Data {
        let client = KavitaClient(address: shelf.server.address)
        switch ServerShelfArtwork.route(for: id, isList: shelf.isList, shelf: shelf.id) {
        case .shelfCoverOfList(let list): return try await client.readingListCover(list)
        case .shelfCoverOfCollection(let tag): return try await client.collectionCover(tag)
        case .chapter(let chapter): return try await client.chapterCover(chapter)
        case .series(let series): return try await client.seriesCover(series)
        case .nothing: return Data()
        }
    }

    private func readMembers() async {
        let client = KavitaClient(address: shelf.server.address)
        if shelf.isList {
            tiles = ServerShelfTiles.of(items: (try? await client.readingListItems(shelf.id)) ?? [])
        } else {
            tiles = ServerShelfTiles.of(series: (try? await client.collected(shelf.id)) ?? [])
        }
    }
}

/// Which cover route one tile of a server's shelf comes from.
///
/// **Four routes and two kinds of shelf, decided here rather than in the view.** A collection
/// asked the reading-list route for its own locked cover until 2026-09-12, and nothing caught
/// it because nothing exercised this card at all — an archive verification said so in those
/// words. The choice is a value now, so a test can state the whole table.
///
/// Android makes the same four choices in `ShelvesScreen.kt`.
enum ServerShelfArtwork: Equatable {
    /// The cover a reader locked on a reading list.
    case shelfCoverOfList(Int)
    /// The cover a reader locked on a collection. Kavita calls a collection a tag.
    case shelfCoverOfCollection(Int)
    /// One entry of a reading list, which is a chapter.
    case chapter(Int)
    /// One member of a collection, which is a series.
    case series(Int)
    /// An id that names neither, which asks for nothing rather than guessing.
    case nothing

    static func route(for id: String, isList: Bool, shelf: Int) -> ServerShelfArtwork {
        if id == ServerShelfCardView.serverCoverID {
            return isList ? .shelfCoverOfList(shelf) : .shelfCoverOfCollection(shelf)
        }
        guard let numeric = Int(id) else { return .nothing }
        return isList ? .chapter(numeric) : .series(numeric)
    }
}

/// Which members of a server's shelf the composite is built from, and in what order.
///
/// **Out of the view because a rule inside a view is a rule no test can reach.** It was inside
/// one, and `ServerShelfCoverTests` answered that by re-implementing the same sort and prefix
/// in its own body — so the suite passed against any view at all, and an adversarial read of
/// this change on 2026-09-12 proved it: changing the view's `prefix` to 3 left all three cases
/// green. The rule is here now and the tests call it.
///
/// A reading list is ordered by the reader, so its items are sorted by that order and named by
/// their chapter. A collection has no order, so its series arrive in the order the server gave
/// them and are named by the series. Android reads the same two rules in `ShelvesScreen.kt`.
enum ServerShelfTiles {

    /// A reading list's first tiles, in the reader's own order.
    static func of(items: [KavitaReadingListItem]) -> [String] {
        items.sorted { $0.order < $1.order }
            .prefix(CompositeCover.tileCount)
            .map { String($0.chapterId) }
    }

    /// A collection's first tiles, in the order the server listed them.
    static func of(series: [KavitaSeries]) -> [String] {
        series.prefix(CompositeCover.tileCount).map { String($0.id) }
    }
}
