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
            let items = (try? await client.readingListItems(shelf.id)) ?? []
            tiles = items.sorted { $0.order < $1.order }
                .prefix(CompositeCover.tileCount)
                .map { String($0.chapterId) }
        } else {
            let series = (try? await client.collected(shelf.id)) ?? []
            tiles = series.prefix(CompositeCover.tileCount).map { String($0.id) }
        }
    }
}
