import SwiftUI

import EpubReaderFeature
import LibraryFeature
import Persistence
import StoryArcCore

/// The three destinations and the search role, as the platform's own tab bar.
///
/// Until this existed the iPhone had **no tab bar at all**: `StoryArcApp` put `LibraryView`
/// straight into the `WindowGroup`, so the app was the shelf and everything else was
/// behind chrome on it. `navigation-shell` asks for three destinations reachable at any
/// time from one persistent control, and for that control not to grow a row when a reader
/// adds a server. This is that control.
///
/// Four things the system gives us here that hand-building would not:
///
/// - **`Tab(role: .search)`** is set apart from the three rather than listed among them —
///   the circular button on the trailing edge — and expands into a field that takes the
///   rest of the bar with it. That is the requirement `navigation-shell` states as *"set
///   apart from them rather than listed among them"*, and it is one argument.
/// - **`.tabViewStyle(.sidebarAdaptable)`** makes the same set the iPad's sidebar without a
///   second navigation to keep in step, and the adaptation is non-destructive: rotating
///   back does not lose the destination, its scroll position or its filters.
/// - **`.tabBarMinimizeBehavior(.onScrollDown)`** is *"chrome that gets out of the way"* —
///   the bar recedes as covers scroll and comes back on the way up, with no animation when
///   the system asks for reduced motion, and no state in which it cannot be recovered.
/// - **A safe area.** The floating search pill this replaces had none, so cover titles at
///   the foot of the grid rendered *behind* it. A real tab bar insets its content.
///
/// The docked-transport slot below the tabs — `tabViewBottomAccessory`, the mini player in
/// the reference the owner supplied — held this comment's predecessor open and empty for a
/// reason it stated honestly: the only transport this app had was EPUB read-aloud, it lived
/// inside a reader presented as a full-screen cover, and speech ended when that cover was
/// dismissed, so there was no navigation behind it to dock to. `read-aloud-beyond-the-reader`
/// moved the session out of the screen — it belongs to ``ReadAloudCentre`` now — and the
/// slot carries ``ReadAloudDock``. Nothing else is put at that edge; it is the app's one
/// persistent transport, because the platform already offers the rest on the lock screen.
struct AppShell: View {
    /// What a tab is worth as a selection.
    ///
    /// The three destinations come from ``LibraryDestination`` rather than being restated,
    /// so the promise that the set never grows is held in one place and tested there.
    /// Search is not one of them: it is a role the platform provides, and giving it a case
    /// here is only how the shell addresses the tab.
    enum Selection: Hashable {
        case destination(LibraryDestination)
        case search
        /// A row the iPad sidebar reveals below the three. Not a destination and never in
        /// the tab bar — see ``SidebarEntry`` and ``LibrarySidebar``.
        case sidebar(SidebarEntry)
    }

    /// Where the reader is. `navigation-shell`: the app opens on the home surface, unless
    /// the launch named somewhere else.
    @Binding var tab: Selection

    let model: LibraryModel
    let progress: ProgressStore?
    let onOpen: (Publication, URL) -> Void
    let onOpenSettings: () -> Void
    /// See ``LibraryView/init(model:surface:progress:onOpen:showLibrary:)``.
    let showLibrary: Int

    var body: some View {
        // Read in `body`, where Observation registers the dependency, rather than inside
        // the accessory's own builder, which SwiftUI may run later. The narrow question —
        // is a session running — and not the book, whose chapter is rewritten on every
        // sentence: the shell has no business redrawing three times a minute for hours.
        let isReadingAloud = ReadAloudCentre.shared.isRunning

        TabView(selection: $tab) {
            Tab(value: .destination(.home)) {
                HomeScreen(
                    model: model,
                    onOpen: onOpen,
                    onOpenSettings: onOpenSettings
                )
            } label: {
                label(Text("tab.home"), LibraryDestination.home.symbolName)
            }

            Tab(value: .destination(.library)) {
                library(.shelf)
            } label: {
                label(Text("tab.library"), LibraryDestination.library.symbolName)
            }

            // Not `library(.onDevice)` any more. That drew the right *set* of covers and
            // nothing else — no queue, no idea what the files weigh, no way to remove one
            // — with the rest of it three taps inside the Settings modal. The destination
            // owns all of it now; see ``DownloadsDestination``.
            Tab(value: .destination(.onDevice)) {
                DownloadsDestination(
                    model: model,
                    onOpen: onOpen,
                    onShowLibrary: { tab = .destination(.library) }
                )
            } label: {
                label(Text("tab.downloads"), LibraryDestination.onDevice.symbolName)
            }

            // The role decides the placement — apart from the three, on the trailing edge
            // — and the expand-into-a-field behaviour. The label is still ours: the system
            // would write its own in the *device's* language, and `localization` lets a
            // reader choose the app's without touching the device's.
            Tab(value: .search, role: .search) {
                library(.search)
            } label: {
                label(Text("tab.search"), "magnifyingglass")
            }

            // The iPad's second half of the same set: library sections and the reader's
            // shelves, under their own headers, hidden from the tab bar so the phone still
            // shows three destinations and the search role and nothing else.
            LibrarySidebar(model: model, onOpen: onOpen) { Selection.sidebar($0) }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        // The docked transport, and the whole of "it reserves no space when absent":
        // without a session the builder produces no content at all, so there is no
        // accessory for the slot to make room for — rather than an empty one, or a hidden
        // one, or a bar of zero height that still insets the destination above it.
        //
        // The `if` is here and not inside ``ReadAloudDock`` deliberately. A view that
        // rendered `EmptyView` would still be *a view* handed to the slot, and whether the
        // system collapses that is the system's business rather than a promise this app
        // can make. `ebook-reader` states the promise, so the app makes it structurally.
        //
        // If a screenshot with no session ever shows the tab bar sitting higher than it
        // does without this modifier, the platform reserves the slot regardless and the
        // answer is `tabViewBottomAccessory(isEnabled:)` — which exists, and is iOS 26.1
        // against a 26.0 floor (ADR-0003), so it would cost an availability branch this
        // app does not otherwise have. Not taken on speculation.
        //
        // The way back is `onOpen` — the same seam the shelf uses to open a cover, taking
        // the publication and its URL. Opening the book that is already being spoken is
        // what `SessionHandover` answers with `adopt`: the reader picks up the sentence
        // the voice is on and the voice never notices. There is no second path back, and
        // that is the point — the one that exists is the one Phase 1 tested.
        .tabViewBottomAccessory {
            if isReadingAloud {
                ReadAloudDock(onReturn: onOpen)
            }
        }
        // `navigation-shell`: leaving search returns the reader to the destination they
        // were on "with its scroll position and filters intact". The query narrows the one
        // library, so a term left behind would follow them onto the shelf and leave it
        // looking half-empty for no reason they could see. The term itself is not lost —
        // the model has already filed it as a recent search.
        .onChange(of: tab) { previous, _ in
            if previous == .search { model.query.search = "" }
        }
        // The library is brought up here rather than by whichever surface happens to be
        // shown first. It used to be started by the shelf's own `.task`, which was
        // correct while the shelf *was* the app — and became a bug the moment a reader
        // could land somewhere else: home opened onto an empty library until they had
        // visited the library tab at least once. `home-screen` says home is assembled
        // from what the device already knows, so what the device knows has to be read
        // before home is drawn.
        .task {
            model.restoreFolders()
            await model.refreshProgress()
        }
    }

    /// One tab's label. Named so the four of them cannot drift apart.
    private func label(_ title: Text, _ symbol: String) -> some View {
        Label {
            title
        } icon: {
            Image(systemName: symbol)
        }
    }

    /// The library, on one of its three faces.
    ///
    /// The same view each time, and deliberately: the shelf, the on-device shelf and
    /// search are one screen over three sets, so a cover looks and behaves the same on all
    /// of them and opens the same reader.
    private func library(_ surface: LibrarySurface) -> some View {
        LibraryView(
            model: model,
            surface: surface,
            progress: progress,
            onOpen: onOpen,
            showLibrary: showLibrary
        )
    }
}
