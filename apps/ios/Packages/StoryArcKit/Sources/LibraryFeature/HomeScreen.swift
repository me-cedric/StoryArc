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

    @State private var isImporting = false
    @State private var isPickingFolder = false

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
                        onOpenFile: { isImporting = true },
                        onAddFolder: { isPickingFolder = true }
                    )
                } else {
                    surface
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.palette.surfaceCanvas)
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
            .importingPublications(into: model, isPresented: $isImporting)
            // `local-library`: a folder picked here is reachable again after a restart,
            // which is what the security-scoped bookmark in the model is for.
            .fileImporter(
                isPresented: $isPickingFolder,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let folder = urls.first {
                    model.addFolder(folder)
                }
            }
        }
    }

    private var surface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoryArcSpace.section) {
                if !keepReading.isEmpty { keepReadingSection }
                if !upNext.isEmpty { upNextSection }
                if !recentlyAdded.isEmpty { recentlyAddedSection }

                shelvesLink

                if !finished.isEmpty {
                    HomeFinished(groups: finished, model: model, onOpen: open)
                }
            }
            .padding(.vertical, StoryArcSpace.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The hero. One on the surface, never two — a second would make neither of them one.
    private var keepReadingSection: some View {
        HomeSection(title: Text("library.continueReading", bundle: .module)) {
            HomeMore(
                title: Text("library.continueReading", bundle: .module),
                publications: keepReading,
                model: model,
                onOpen: open
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
            HomeMore(
                title: Text("home.upNext", bundle: .module),
                publications: upNext,
                model: model,
                onOpen: open
            )
        } content: {
            HomeShelfRow(publications: upNext, model: model, onOpen: open)
        }
    }

    private var recentlyAddedSection: some View {
        HomeSection(title: Text("home.recentlyAdded", bundle: .module)) {
            HomeMore(
                title: Text("home.recentlyAdded", bundle: .module),
                publications: HomeShelves.recentlyAdded(in: model.publications, limit: .max),
                model: model,
                onOpen: open
            )
        } content: {
            HomeShelfRow(publications: recentlyAdded, model: model, onOpen: open)
        }
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
