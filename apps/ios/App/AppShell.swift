import SwiftUI

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
/// the reference the owner supplied — is **reserved and deliberately empty**. The only
/// transport this app has is EPUB read-aloud, it lives inside a reader presented as a
/// full-screen cover, and speech ends when that cover is dismissed: making it outlive the
/// reader is a capability change with a proposal of its own, not a layout change that can
/// ride along here. Nothing else is put at that edge, so the slot stays free for it.
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
        TabView(selection: $tab) {
            Tab(value: .destination(.home)) {
                HomeDestination(
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

            Tab(value: .destination(.onDevice)) {
                library(.onDevice)
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
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        // `navigation-shell`: leaving search returns the reader to the destination they
        // were on "with its scroll position and filters intact". The query narrows the one
        // library, so a term left behind would follow them onto the shelf and leave it
        // looking half-empty for no reason they could see. The term itself is not lost —
        // the model has already filed it as a recent search.
        .onChange(of: tab) { previous, _ in
            if previous == .search { model.query.search = "" }
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
