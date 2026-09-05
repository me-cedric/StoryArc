import SwiftUI

import StoryArcCore

/// The library beside the page on a wide window, and the library alone everywhere else.
///
/// Split out of `LibraryView.swift` because that file sits eleven lines under SwiftLint's
/// 400-line cap and `swiftlint --strict` makes the warning an error. The seam is a real one:
/// everything here answers one question — which navigation container a cover's link lands in
/// — and nothing else in the view answers it at all.
///
/// ## What was decided, and what was rejected
///
/// `publication-detail` asks for the page "beside the library rather than over it" in a wide
/// window, and iOS had no second pane to put it in. Three shapes could have given it one:
///
/// 1. **A `NavigationSplitView` as the shell**, replacing the `TabView`.
/// 2. **A hybrid** — the split on iPad, the tab bar on iPhone.
/// 3. **A split inside the destination**, which is this.
///
/// The first two are refused by `native-experience`, not by taste. *The two platforms reach
/// the same destinations differently* states the mechanism outright: "iOS presents it as a
/// tab bar that adapts into a sidebar in a wide window". A shell that stops being a tab bar on
/// an iPad stops satisfying that sentence, and a hybrid stops satisfying it on exactly the
/// device this work is for. ``AppShell`` keeps its `TabView`, its `.sidebarAdaptable`, its
/// minimise behaviour and its bottom accessory, and none of them is touched from here.
///
/// So the split is *inside* the Library destination, which is the thing `publication-detail`
/// names — "beside **the library**". That also answers the tombstone this change deletes from
/// `PublicationRoute.swift`, which feared "a second, disagreeing navigation": a list and its
/// detail are not a second destination set. Nothing in this file names a destination, and the
/// three the shell offers are unchanged and unchanged in number.
///
/// ## Why the whole shelf is not given a pane
///
/// Home keeps its stack, and deliberately. *Tablet and large screens* says the content area
/// "shows the destination the reader is in and nothing else — the home surface's continue
/// row, or the library's cover grid". Home's content area is the editorial surface; a pane
/// permanently open beside it, holding a sentence about covers, is the second thing that
/// clause forbids. Downloads, Search and the sidebar's own rows keep the push for a plainer
/// reason: each composes its own `NavigationStack` with destinations of its own, this pass
/// can photograph none of them, and a pane added to a surface nobody has watched is a
/// guess. That inconsistency is real, it is named in the handoff, and it is one file each to
/// close once the frames exist.
extension LibraryView {

    /// The navigation container this surface is composed in.
    ///
    /// **The registration of ``View/publicationPages(in:onOpen:)`` is the load-bearing line
    /// in this file, and it appears once per branch.** A `NavigationLink(value:)` resolves
    /// against the nearest enclosing container that declares a `navigationDestination` for
    /// that type. In the split branch the leading column declares none, so a cover's
    /// `PublicationRoute` falls through to the split view, which — this is the documented
    /// behaviour of `NavigationSplitView`, "tapping a `NavigationLink` that appears in an
    /// earlier column sets the view that the stack displays over its root view" — puts the
    /// page in the detail column over the empty-pane sentence. Register it in *both* columns
    /// and the leading one wins, the page pushes over the shelf, and the second pane never
    /// draws anything. `PublicationPaneTests` fails if it moves.
    ///
    /// One container, never two chosen by width. A branch on the size class would rebuild the
    /// whole subtree the moment an iPad left Split View, and *A layout the window is too small
    /// for* requires widening to restore the second pane "without losing position". The
    /// platform's own collapse is what keeps that promise: below the regular size class the
    /// split becomes one stack, a cover pushes, and back returns to the shelf — which is what
    /// the phone already did, drawn by a different container.
    @ViewBuilder
    var container: some View {
        if surface == .shelf {
            NavigationSplitView(preferredCompactColumn: $compactColumn) {
                libraryColumn
                    // The leading column is the *shelf*, not a list of places to go, so it is
                    // given a shelf's width rather than a sidebar's ~320 points.
                    // ``CoverGrid`` steps its covers up past 900 points of shelf; below about
                    // 320 the grid is down to one column, which is the floor this refuses to
                    // go under whatever the window does.
                    .navigationSplitViewColumnWidth(min: 320, ideal: 480, max: 760)
            } detail: {
                NavigationStack {
                    PublicationDetailPlaceholder()
                        .publicationPages(in: model, onOpen: onOpen)
                        // A server browsed from the shelf's own offer lands beside the shelf
                        // too, rather than over it. It is the same verb as choosing a cover —
                        // *show me this* — and giving it the other column would put the one
                        // navigation this screen has in two places.
                        .navigationDestination(item: $browsing) { id in
                            if let source = model.registry[id] { browser(for: source) }
                        }
                }
            }
            // `.balanced`, because the leading column is the point of the screen. The default
            // gives the detail column prominence and lets the other one be pushed aside, which
            // is right when the first column is a table of contents and wrong when it is the
            // library.
            .navigationSplitViewStyle(.balanced)
            // The split view offers its own sidebar toggle, and on an iPad the shell already
            // draws one for `.sidebarAdaptable`. Two toggles a thumb apart, meaning different
            // things, is the "second, disagreeing navigation" for real — and a reader who
            // collapsed the shelf away would be left on a destination showing none of it.
            .toolbar(removing: .sidebarToggle)
        } else {
            NavigationStack {
                libraryColumn
                    .publicationPages(in: model, onOpen: onOpen)
                    .navigationDestination(item: $browsing) { id in
                        if let source = model.registry[id] { browser(for: source) }
                    }
            }
        }
    }

    /// The way in to one source, wherever it is being shown from.
    ///
    /// Not reachable from the shelf any more, and deliberately so: a configured server is
    /// not a place to go. It is reached from search, which is the tier `library-browsing`
    /// calls *reachable* — everything a server has that the app has not cached.
    func browser(for source: Source) -> some View {
        SourceBrowser(
            source: source,
            pins: pins,
            credentials: credentials,
            kavitaProgress: kavitaProgress,
            lists: model.serverLists,
            onOpen: onOpen,
            // Carried in so the server is asked the question the reader already typed,
            // rather than being opened at its list of libraries with an empty field.
            searching: serverSearch,
            onRetry: { await model.test(source) }
        )
    }
}
