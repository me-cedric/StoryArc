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
    let shelf: RememberedShelf
    let page: KavitaPage

    @State private var plan: HomeShelfCoverPlan = .blank
    @State private var covers: [String: CGImage] = [:]

    private static let soleCoverID = "sole-cover"

    var body: some View {
        Group {
            switch plan {
            case .blank:
                NamedCoverlessWell(name: shelf.title)
            case .sole, .composite:
                ShelfComposite(tiles: tiles, covers: covers)
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

    private func lockedCover(_ client: KavitaClient) async -> CGImage? {
        do {
            let data = shelf.kind == .readingList
                ? try await client.readingListCover(shelf.serverID)
                : try await client.collectionCover(shelf.serverID)
            return Self.decode(data)
        } catch {
            return nil
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
        let data = try? await (shelf.kind == .readingList
            ? client.chapterCover(numeric)
            : client.seriesCover(numeric))
        return data.flatMap(Self.decode)
    }

    private static func decode(_ data: Data) -> CGImage? {
        #if canImport(UIKit)
        UIImage(data: data)?.cgImage
        #else
        nil
        #endif
    }
}

/// The blank a Kavita shelf draws when nothing answered: no locked cover, and no member's
/// cover fetched either.
///
/// `library-browsing`'s D1 ("iOS shelf with no artwork draws a blank frame") asks the blank to
/// carry the shelf's name rather than an empty frame, the way Android's `ShelfComposite`
/// already does through `CoverlessWell(title = name, format = null)`. That fix is task 7.11's,
/// reaching `ShelfComposite` and `CoverlessWell.swift` for every caller of both; this is the
/// smaller thing this task alone needs, scoped to the one new caller it adds. iOS's shared
/// `CoverlessWell` still wants a `PublicationFormat` it has none of here — a shelf, not a
/// publication — so this does not reach for it.
private struct NamedCoverlessWell: View {
    @Environment(\.theme) private var theme
    let name: String

    var body: some View {
        ZStack {
            theme.palette.surfaceRaised
            Text(name)
                .textRole(.caption)
                .foregroundStyle(theme.palette.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(StoryArcSpace.xs)
        }
        // The caption under the card already states the name. Spoken here as well would say
        // it twice.
        .accessibilityHidden(true)
    }
}
