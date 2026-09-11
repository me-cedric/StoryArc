internal import SwiftUI

internal import DesignSystem
internal import Persistence
internal import StoryArcCore

/// One of the home surface's two shelves of shelves.
///
/// `collections-and-reading-lists`, *Shelves on the home surface*. The caller draws it only
/// when its half holds something — a heading over a gap is the surface looking like it is
/// waiting for something, which is the one thing it must never do.
///
/// **The heading leads to ``ShelvesView``, not to a filtered library.** Every other heading
/// here leads to "the full list in the library, filtered to match the shelf", and a collection
/// is not a library filter: the exhaustive list of collections is a screen of its own, and it
/// is the only place a shelf is made, renamed or deleted. `HomeScreen`'s `pinnedSections`
/// makes the same argument from the other side, where the shelf is a collection's *contents*.
///
/// Android's `homeShelvesShelf` is the same shelf.
struct HomeShelvesRow: View {
    let title: LocalizedStringKey
    let summaries: [HomeShelfSummary]
    let model: LibraryModel
    /// The Kavita servers this device can open, by source id — see ``KavitaPage/pages(in:)``.
    let pages: [UUID: KavitaPage]
    let onOpen: (Publication, URL) -> Void

    var body: some View {
        HomeSection(title: Text(title, bundle: .module)) {
            ShelvesView(model: model, onOpen: onOpen)
        } content: {
            row
        }
    }

    private var row: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: StoryArcSpace.rowCoverGap) {
                ForEach(summaries) { summary in
                    NavigationLink {
                        destination(of: summary)
                    } label: {
                        card(summary)
                    }
                    .buttonStyle(.plain)
                    // A shelf is a composite of four covers, and four covers below about 150
                    // points stop being four covers — the floor `ShelvesView`'s own grid
                    // takes, rather than a cover cell's.
                    .frame(width: 150)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, StoryArcSpace.gutter, for: .scrollContent)
    }

    /// The card itself: ``ShelfCard``, unchanged, because this surface and the shelves screen
    /// draw the same thing and a second card would eventually be a different one.
    private func card(_ summary: HomeShelfSummary) -> some View {
        ShelfCard(
            model: model,
            title: summary.name,
            subtitle: shelfSubtitle(count: summary.count, sourceName: summary.sourceName),
            tiles: summary.tiles.map(\.id),
            progress: summary.progress
        )
    }

    /// Where a card leads.
    ///
    /// A shelf the reader made opens its own detail screen, as it does from the shelves
    /// screen. A shelf a server defined opens that server's page for it, which is where an
    /// unreachable server is reported — and reporting it there is what keeps this surface
    /// silent about the network.
    ///
    /// A remembered shelf whose source this device cannot open is not on this surface at all,
    /// so the last branch is unreachable; it is written rather than trapped, because a view
    /// that cannot be built is a crash and an empty one is a dead end the reader can leave.
    @ViewBuilder
    private func destination(of summary: HomeShelfSummary) -> some View {
        switch summary.destination {
        case let .onDevice(id):
            if summary.kind == .readingList {
                ReadingListDetail(model: model, id: id)
            } else {
                CollectionDetail(model: model, id: id)
            }

        case let .onServer(shelf):
            if let page = pages[shelf.sourceID] {
                if shelf.kind == .readingList {
                    KavitaListView(server: page, listID: shelf.serverID, title: shelf.title, onOpen: onOpen)
                } else {
                    KavitaCollectionView(
                        server: page,
                        collectionID: shelf.serverID,
                        title: shelf.title,
                        onOpen: onOpen
                    )
                }
            } else {
                EmptyView()
            }
        }
    }

}

/// What a shelf's card says under its name: where it came from, and how much is in it.
///
/// One function for the home surface and the shelves screen, because it is one sentence. A
/// remembered shelf has no count this device can vouch for, so it states its source alone
/// rather than a zero — and a shelf the reader made here has no source, so it states the
/// count alone.
func shelfSubtitle(count: Int?, sourceName: String?) -> String {
    let items = count.map { count in
        String(
            format: String(localized: "shelves.count \(count)", bundle: .module, locale: .storyArc),
            count
        )
    }
    return [sourceName, items].compactMap { $0 }.joined(separator: " · ")
}

extension KavitaPage {
    /// Every Kavita server this device can actually open, by source id.
    ///
    /// Read once rather than per card: the key comes out of the secure store, and a computed
    /// property on a view would ask it again on every redraw. A source that is not a Kavita
    /// server, has no address, or has lost its key is absent — which is also what decides
    /// whether its remembered shelves are named at all, so the two are one lookup.
    static func pages(in registry: SourceRegistry, credentials: CredentialStore?) -> [UUID: KavitaPage] {
        var found: [UUID: KavitaPage] = [:]
        for source in registry.sources {
            if let page = KavitaPage(source: source, credentials: credentials) {
                found[source.id] = page
            }
        }
        return found
    }
}
