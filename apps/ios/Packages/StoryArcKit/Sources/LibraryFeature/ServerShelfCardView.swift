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
    private static let serverCover = "server-cover"

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
        if id == Self.serverCover {
            return try await client.readingListCover(shelf.id)
        }
        guard let numeric = Int(id) else { return Data() }
        return shelf.isList
            ? try await client.chapterCover(numeric)
            : try await client.seriesCover(numeric)
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
