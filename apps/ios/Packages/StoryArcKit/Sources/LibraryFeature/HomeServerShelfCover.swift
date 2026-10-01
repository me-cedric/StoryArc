internal import SwiftUI

internal import DesignSystem
internal import Kavita
internal import StoryArcCore

/// What a Kavita shelf's card draws on the home surface, decided from what the server
/// answered.
///
/// `sources`' field report: "Kavita collections and reading lists on Home show only a title,
/// no cover." ``HomeShelfSummary/tiles`` is empty for every remembered server shelf —
/// ``HomeShelfIndex/assemble`` never reaches a source, by `home-screen`'s own rule — so
/// nothing had ever asked a server for this card's artwork at all. This is the order the
/// field report's own decision states: the server's own cover, then the first members', then
/// a named blank.
///
/// Pure, so the branch a fetch cannot force a test into can be asserted directly.
/// ``HomeServerShelfCover`` is the one thing that cannot be: it is a network answer, and the
/// existing `ServerShelfCoverTests` suite draws the same line — the routing and the tile
/// selection are tested, the view that fetches is not.
enum HomeShelfCoverPlan: Equatable {
    /// The server's own locked cover, drawn whole.
    case sole
    /// The first members, composited the way a local shelf's are.
    case composite([String])
    /// Nothing answered: no locked cover and no member drew one either.
    case blank

    /// `covered` is the members whose cover arrived. A member with no cover is not a tile:
    /// ``ShelfComposite`` draws an empty frame for it, and a shelf whose members all failed
    /// would be the blank frame D1 names instead of the named well.
    static func decide(hasLockedCover: Bool, memberIDs: [String], covered: Set<String>) -> HomeShelfCoverPlan {
        if hasLockedCover { return .sole }
        let drawn = memberIDs.filter(covered.contains)
        return drawn.isEmpty ? .blank : .composite(drawn)
    }
}

/// A Kavita shelf's own artwork, fetched for the home surface.
///
/// The Shelves screen's ``ServerShelfCardView`` already draws this for a live ``ServerShelf``,
/// which carries ``ServerShelf/chosenCover`` — whether the collection or list's own cover is
/// locked, read from the same listing that named it. A ``RememberedShelf`` carries none of
/// that: it is the shelf's name and numbering, written down so the home surface never has to
/// ask a server just to draw a card ­— see `RememberedShelf`'s own reasoning. Rather than
/// growing the stored token for one avoided request, this tries the locked-cover route
/// unconditionally and reads a refusal the same way a missing lock does: fall to the next
/// step. Kavita's own `Image/collection-cover` and `Image/readinglist-cover` answer an unset
/// cover with an error rather than a placeholder, so `try?` already tells the two apart.
struct HomeServerShelfCover: View {
    let model: LibraryModel
    let shelf: RememberedShelf
    let page: KavitaPage

    @State private var plan: HomeShelfCoverPlan = .blank
    @State private var covers: [String: CGImage] = [:]

    private static let soleCoverID = "sole-cover"

    var body: some View {
        Group {
            switch plan {
            case .blank:
                // The caption under the card already states the name. Spoken here as
                // well would say it twice.
                CoverlessWell(name: shelf.title, format: nil)
                    .accessibilityHidden(true)
            case .sole, .composite:
                ShelfComposite(tiles: tiles, covers: covers, name: shelf.title)
            }
        }
        .task(id: shelf.id) { await load() }
    }

    /// The ids ``ShelfComposite`` draws, for whichever plan answered.
    private var tiles: [String] {
        switch plan {
        case .sole: [Self.soleCoverID]
        case let .composite(ids): ids
        case .blank: []
        }
    }

    private func load() async {
        let client = KavitaClient(address: page.address)
        let locked = await lockedCover(client)
        if let locked {
            covers[Self.soleCoverID] = locked
            plan = .decide(hasLockedCover: true, memberIDs: [], covered: [])
            return
        }

        let memberIDs = await memberIDs(client)
        for id in memberIDs {
            if let image = await memberCover(client, id: id) {
                covers[id] = image
            }
        }
        plan = .decide(hasLockedCover: false, memberIDs: memberIDs, covered: Set(covers.keys))
    }

    /// Cached the same way a local shelf's cover is -- task 22.2's own correction. See
    /// ``lockedCoverID(server:shelf:)`` for how the cache id is scoped.
    private func lockedCover(_ client: KavitaClient) async -> CGImage? {
        await model.serverCover(
            for: Self.lockedCoverID(server: page.id, shelf: shelf),
            maxPixelSize: Self.coverPixelSize
        ) {
            shelf.kind == .readingList
                ? try await client.readingListCover(shelf.serverID)
                : try await client.collectionCover(shelf.serverID)
        }
    }

    private func memberIDs(_ client: KavitaClient) async -> [String] {
        if shelf.kind == .readingList {
            let items = (try? await client.readingListItems(shelf.serverID)) ?? []
            return ServerShelfTiles.of(items: items)
        }
        let series = (try? await client.collected(shelf.serverID)) ?? []
        return ServerShelfTiles.of(series: series)
    }

    private func memberCover(_ client: KavitaClient, id: String) async -> CGImage? {
        guard let numeric = Int(id) else { return nil }
        let kind = shelf.kind == .readingList ? "chapter" : "series"
        return await model.serverCover(
            for: "srv:\(page.id):\(kind):\(numeric)",
            maxPixelSize: Self.coverPixelSize
        ) {
            try await (shelf.kind == .readingList
                ? client.chapterCover(numeric)
                : client.seriesCover(numeric))
        }
    }

    /// ``ShelfCover``'s own default width (180 points) at a plausible @2x, since this view
    /// has no display scale of its own to size the decode from -- it runs from `.task`,
    /// off the view hierarchy that would give it one. A cache key one shelf's own scale off
    /// from the pixels it draws costs a re-fetch, not a wrong image.
    private static let coverPixelSize = 360

    /// The disk cache id of a shelf's locked cover.
    ///
    /// Two servers can use the same number, so the id names the server. A reading list and
    /// a collection on one server also number separately, so the id names the kind too.
    /// Android's `homeShelfArtwork` scopes its id the same way.
    static func lockedCoverID(server: String, shelf: RememberedShelf) -> String {
        "srv:\(server):lock-\(shelf.kind.rawValue):\(shelf.serverID)"
    }
}

// The blank a Kavita shelf draws when nothing answered — no locked cover, and no member's
// cover fetched either — is `CoverlessWell(name:format:)`, task 7.11's reach into
// `ShelfComposite` and `CoverlessWell.swift` for every caller of both. This file no longer
// carries a well of its own.
