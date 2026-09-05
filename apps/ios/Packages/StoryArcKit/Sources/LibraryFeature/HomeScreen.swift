public import SwiftUI

public import StoryArcCore
internal import DesignSystem
internal import UniformTypeIdentifiers

/// Home: what the reader is in the middle of, and the way to everything else.
///
/// The first destination and where the app opens. There was no such screen before the
/// shell existed — the closest thing was a *Continue reading* row inside the cover grid,
/// hidden the moment a search or a selection started, which took the app's one editorial
/// moment away exactly when a reader was looking hardest.
///
/// A comics library has no editors, so **StoryArc generates its own editorial**: a hero
/// carousel of what is part-read, then the next issue of each series that has been started,
/// then what arrived lately, then a dated shelf of what has been finished. Every heading
/// leads to the whole of its shelf, because Home is deliberately never exhaustive — that is
/// what the Library destination is for.
///
/// **The property that matters most is what this screen does not do.** Every shelf below is
/// assembled from publications the app already holds and reading records it already wrote.
/// Nothing here opens a connection, and nothing waits for one: `home-screen` requires the
/// surface to render complete and immediately in airplane mode, "with the same shelves in
/// the same order as when the sources are up", and what cannot be opened right now is
/// dimmed rather than removed. A shelf that shrank when the Wi-Fi dropped would read as
/// lost reading to somebody who lost nothing.
///
/// It degrades by *absence* rather than by emptiness — no section is ever drawn as a
/// heading over a gap — and a library with nothing in it at all leaves one sentence and the
/// two ways out.
public struct HomeScreen: View {
    @Environment(\.theme) private var theme

    private let model: LibraryModel
    private let onOpen: (Publication, URL) -> Void
    private let onOpenSettings: () -> Void

    /// Which local picker is up, if either.
    ///
    /// One optional rather than two booleans, for the reason ``LocalPick`` gives: this screen
    /// declared a `fileImporter` for each and SwiftUI presents only the last one applied. Home
    /// had them in the opposite order to the shelf, so the defect here was the mirror image —
    /// *Add a folder* worked and *Open a comic* opened nothing, on the empty state a reader
    /// with nothing configured lands on first.
    @State private var picking: LocalPick?

    /// Which shelves the reader asked to see here. Written by ``ShelvesView``, read here —
    /// one scalar in the same `UserDefaults` as the library's other choices, and deliberately
    /// not a field on ``LibraryModel``: see ``PinnedShelves``.
    @AppStorage(PinnedShelves.storageKey) private var pinnedShelves = ""

    public init(
        model: LibraryModel,
        onOpen: @escaping (Publication, URL) -> Void = { _, _ in },
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.model = model
        self.onOpen = onOpen
        self.onOpenSettings = onOpenSettings
    }

    // MARK: - The shelves

    /// Where the reader stopped, most recently first.
    ///
    /// Taken from the model's own projection rather than recomputed here: it is the
    /// property `library-browsing` already specifies and already tests, and Home having its
    /// own idea of what "in progress" means is how the two would come to disagree.
    private var keepReading: [Publication] { model.continueReading }

    private var upNext: [Publication] {
        HomeShelves.upNext(in: model.publications) { model.record(of: $0) }
    }

    private var recentlyAdded: [Publication] {
        HomeShelves.recentlyAdded(in: model.publications)
    }

    private var finished: [HomeShelves.FinishedGroup] {
        HomeShelves.finished(in: model.publications) { model.record(of: $0) }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if model.publications.isEmpty {
                    HomeEmpty(
                        onOpenFile: { picking = .file },
                        onAddFolder: { picking = .folder }
                    )
                } else {
                    surface
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.palette.surfaceCanvas)
            // Once, at the root of this stack, for every cover below it — the shelves here,
            // the *see all* grids they lead to, the shelves screen, a collection's grid, and
            // the series shelf on the page itself. `publication-detail` requires the page to
            // open "within the destination they were already in", which is what a push onto
            // this stack is.
            .publicationPages(in: model, onOpen: onOpen)
            // The same soft edge the shelf uses: what passes under this app's chrome is
            // artwork, and a hard cut across a cover looks like a rendering fault.
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationTitle(Text("home.title", bundle: .module))
            .toolbar {
                // The only trailing item, and the reason Settings could leave the library's
                // toolbar: it is not something done to the shelf.
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onOpenSettings) {
                        Label {
                            Text("library.settings", bundle: .module)
                        } icon: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            // Reading history is read *after* the library is, and again each time the walk
            // finishes. The order is the whole point: positions are matched to
            // publications, so a read taken while the shelf is still empty matches nothing
            // and files nothing — and the app keeps no publications between launches, so
            // on a cold start the shelf is *always* still empty for a moment. Home opened
            // with no Keep reading and no Up next until the reader visited the library tab,
            // which is precisely the class of bug the shell was built to end.
            .task { await model.refreshProgress() }
            .onChange(of: model.scanState) { _, state in
                if case .finished = state { Task { await model.refreshProgress() } }
            }
            // `local-library`, both halves, through one presentation — see
            // ``LocalPickerTests``. A folder picked here is reachable again after a restart,
            // and a file handed over is copied into storage the app owns.
            .pickingLocalLibrary(into: model, pick: $picking)
        }
    }

    private var surface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoryArcSpace.section) {
                if !keepReading.isEmpty { keepReadingSection }
                if !upNext.isEmpty { upNextSection }
                if !recentlyAdded.isEmpty { recentlyAddedSection }

                pinnedSections

                shelvesLink

                if !finished.isEmpty {
                    HomeFinished(groups: finished, model: model)
                }
            }
            .padding(.vertical, StoryArcSpace.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The hero. One on the surface, never two — a second would make neither of them one.
    ///
    /// **The one shelf on Home that still opens the book.** `publication-detail` sends every
    /// cover to the publication's page and exempts resuming, and `home-screen` says the same
    /// thing from the other side: choosing from Keep reading opens at the recorded position
    /// "without an intermediate screen". A reader who taps a card that says how much is left
    /// has already decided.
    ///
    /// Its *heading* still leads to `HomeMore`, which is the library's own grid over the same
    /// set — `home-screen` words that as "the full list in the library, filtered to match the
    /// shelf" — so the covers there lead to the page like every other cover in that grid. The
    /// resume affordance is the hero, not the set of publications behind it.
    private var keepReadingSection: some View {
        HomeSection(title: Text("library.continueReading", bundle: .module)) {
            HomeMore(
                title: Text("library.continueReading", bundle: .module),
                publications: keepReading,
                model: model
            )
        } content: {
            HomeHero(publications: keepReading, model: model, onOpen: open)
        }
    }

    /// The next issue of a series that has been started — Komga's *On Deck*.
    ///
    /// A shelf of its own rather than more cards in the hero, because it answers a
    /// different question: the hero is *where you stopped*, this is *what to start next*,
    /// and the two never offer the same publication at the same time.
    private var upNextSection: some View {
        HomeSection(title: Text("home.upNext", bundle: .module)) {
            HomeMore(title: Text("home.upNext", bundle: .module), publications: upNext, model: model)
        } content: {
            HomeShelfRow(publications: upNext, model: model)
        }
    }

    private var recentlyAddedSection: some View {
        HomeSection(title: Text("home.recentlyAdded", bundle: .module)) {
            HomeMore(
                title: Text("home.recentlyAdded", bundle: .module),
                publications: HomeShelves.recentlyAdded(in: model.publications, limit: .max),
                model: model
            )
        } content: {
            HomeShelfRow(publications: recentlyAdded, model: model)
        }
    }

    /// The shelves the reader asked to see here, one section each.
    ///
    /// `home-screen`, *Pinned shelves*: a pinned collection or reading list "appears on the
    /// home surface as a shelf of its own", and *The rest of the home surface* fixes where —
    /// "recently added publications, the reader's pinned shelves, and what they have
    /// finished", in that order. So these sit between recently added and finished.
    ///
    /// **A shelf with nothing in it is not drawn**, per *A shelf that would be empty*, and
    /// that is not only about a collection the reader emptied: a pinned shelf whose members
    /// are all on a source that has not been scanned yet resolves to nothing, and a heading
    /// over no covers would be the surface waiting on something — which is the one thing this
    /// screen must never look like it is doing.
    ///
    /// A pin whose shelf has been deleted resolves to nothing too, and is simply absent. The
    /// stored pin is left alone rather than tidied up: writing to storage while drawing is
    /// how a redraw becomes a write, and an orphan token costs one lookup that already fails.
    @ViewBuilder
    private var pinnedSections: some View {
        let pinned = PinnedShelves(stored: pinnedShelves)
        ForEach(pinnedCollections(pinned), id: \.id) { collection in
            let publications = model.publications.filter { collection.members.contains($0.id) }
            if !publications.isEmpty {
                HomeSection(title: Text(verbatim: collection.name)) {
                    HomeMore(title: Text(verbatim: collection.name), publications: publications, model: model)
                } content: {
                    HomeShelfRow(publications: publications, model: model)
                }
            }
        }
        ForEach(pinnedLists(pinned), id: \.id) { list in
            // A reading list keeps its own order, which is the whole difference between the
            // two types — so the entries are walked rather than the library filtered.
            let publications = list.entries.compactMap { entry in
                model.publications.first { $0.id == entry }
            }
            if !publications.isEmpty {
                HomeSection(title: Text(verbatim: list.name)) {
                    HomeMore(title: Text(verbatim: list.name), publications: publications, model: model)
                } content: {
                    HomeShelfRow(publications: publications, model: model)
                }
            }
        }
    }

    private func pinnedCollections(_ pinned: PinnedShelves) -> [PublicationCollection] {
        model.shelves.collections.filter { pinned.contains(.collection($0.id)) }
    }

    private func pinnedLists(_ pinned: PinnedShelves) -> [ReadingList] {
        model.shelves.lists.filter { pinned.contains(.list($0.id)) }
    }

    /// Collections and reading lists, which the library's toolbar used to hold.
    ///
    /// A row on Home rather than a fourth destination: a shelf is something a reader made,
    /// so it belongs beside what they are reading, and `navigation-shell` is explicit that
    /// the destination set is three.
    private var shelvesLink: some View {
        NavigationLink {
            ShelvesView(model: model, onOpen: onOpen)
        } label: {
            HStack(spacing: StoryArcSpace.sm) {
                Image(systemName: "square.stack")
                Text("shelves.title", bundle: .module)
                Spacer()
                Image(systemName: "chevron.right")
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
            }
            .textRole(.body)
            .foregroundStyle(theme.palette.textPrimary)
            .padding(.horizontal, StoryArcSpace.gutter)
            .frame(minHeight: StoryArcSpace.xxl)
            // §3.11's `maxContentWidth`, and the one row on Home that needed it. Every
            // other thing here is a shelf that scrolls, so it *should* run to the window's
            // edge; this is a label with a chevron pushed to the far side of it, and on a
            // 13-inch iPad the two ended up a foot apart with nothing in between. Leading
            // rather than centred, so it starts on the same gutter the shelves do.
            .frame(maxWidth: SidebarLayout.maxContentWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// `home-screen`: choosing something from Home opens it at the recorded position
    /// "without an intermediate screen".
    private func open(_ publication: Publication) {
        if let url = model.location(of: publication) { onOpen(publication, url) }
    }
}
