public import SwiftUI

internal import StoryArcCore

/// The search surface's own chrome: the field, the scope bar, and what sits under them.
///
/// Split out of `LibraryView.swift` when that file crossed the 400-line cap `pnpm lines:check`
/// enforces. The seam is a real one rather than a place to cut: everything here is conditional
/// on ``LibrarySurface/search`` and nothing else in the view is, so the shelf and the
/// on-device shelf now read without the search branch threaded through them.
extension LibraryView {
    /// The field, and only on the surface that owns one.
    ///
    /// The shelf has no field at all, and `navigation-shell` asks for search to be reached one
    /// way rather than two. A second field on the shelf was the floating pill that cover
    /// titles were rendering behind.
    ///
    /// **This comment used to say the field was the shell's**, offered as `Tab(role: .search)`
    /// — "the system's own control, set apart from the three destinations, expanding into a
    /// field and taking the rest of the bar with it". That control is gone: expanding into a
    /// field *in place* is exactly the shape-changing the requirement now forbids, and there
    /// was no screen behind it to land on. Search is a plain fourth tab leading here, and the
    /// field is this screen's own `.searchable`.
    ///
    /// What the field is *over* changed earlier, and for a related reason. It used to be the
    /// shelf, narrowed — which made search a filter over what this device happens to hold, and
    /// left a reader's servers out of the only question they were being asked. Now a term puts
    /// up ``SearchResultsView``, one answer from every library the reader has, and no term at
    /// all puts up ``SearchAtRest`` rather than the shelf.
    @ViewBuilder
    func searching(_ inner: some View) -> some View {
        if surface == .search {
            searchSurface(inner)
                .searchable(
                    text: searchBinding,
                    prompt: Text("library.search.prompt", bundle: .module)
                )
                // **No `.searchSuggestions`.** It drew the recent queries — which was the
                // missing half at the time, since no iOS reader had ever seen one — but it
                // draws them as a list *attached to the field*, visible only while the field
                // has focus. `navigation-shell` now asks for a screen a reader lands on with
                // headed sections they can scroll before deciding to type, and three shelves
                // of covers do not belong in a completion dropdown. ``SearchAtRest`` draws
                // the recents and the suggestions together, below.
                //
                // The platform's own segmented scope bar, which is the iOS idiom — Android
                // uses filter chips, because Material retired the segmented button in the
                // Expressive update. `library-browsing`: the screen "states whether it is
                // searching everything or only what is on the device", and a reader can
                // narrow and widen it "without leaving the screen".
                //
                // `LibraryAvailability`, not a `SearchScope` of its own: it already means
                // exactly this, already says it in four languages, and already answers
                // `keeps(_:)` the way the shelf asks it. Two names for one idea would drift
                // on the day one of them gained a third case.
                .searchScopes($searchScope, activation: .onSearchPresentation) {
                    ForEach(LibraryAvailability.allCases, id: \.self) { scope in
                        Text(scope.titleKey, bundle: .module).tag(scope)
                    }
                }
                // The one place the question is asked. Bound to the model's own term rather
                // than to a second piece of state, so a recent search chosen from
                // ``SearchAtRest`` runs exactly as if it had been typed.
                //
                // `initial: true` because the term outlives the session: `library-browsing`
                // keeps the query, so a reader who left mid-search and came back would
                // otherwise find the screen narrowed by a term with no results under it and
                // nothing asked of any server.
                .onChange(of: model.query.search, initial: true) { _, term in
                    search.ask(
                        term,
                        in: model,
                        credentials: credentials,
                        pins: pins,
                        scope: searchScope
                    )
                }
                // Narrowing re-asks rather than filtering what is already on screen, because
                // the scope decides *who is asked* and not only what is shown: widening from
                // the device has to start the fan-out that narrowing stopped.
                .onChange(of: searchScope) { _, scope in
                    search.ask(
                        model.query.search,
                        in: model,
                        credentials: credentials,
                        pins: pins,
                        scope: scope
                    )
                }
                .onDisappear { search.clear() }
        } else {
            inner
        }
    }

    /// What search opens onto, or the answer to what was typed.
    ///
    /// **`inner` — the shelf — is deliberately not used here any more.** It was: with nothing
    /// typed, the search surface drew the whole library grid waiting to be narrowed, which is
    /// what made search read as a filter over a shelf rather than as a place. The shelf is one
    /// tab away and exhaustive; this screen offers, per `navigation-shell`.
    @ViewBuilder
    private func searchSurface(_ inner: some View) -> some View {
        if search.isSearching {
            SearchResultsView(
                listing: search.listing,
                // A row a server answered leads to that server, opened on the question
                // rather than at its front door — and never to the publication page, which
                // resolves against the library's own set and would say the publication is
                // gone. The row already names the library; this is where the reader arrives
                // in it.
                onFollow: { route in
                    serverSearch = search.listing.term
                    browsing = UUID(uuidString: route.sourceID)
                },
                onRetry: { id in
                    search.retry(id, in: model, credentials: credentials, pins: pins)
                }
            )
        } else {
            SearchAtRest(
                model: model,
                scope: $searchScope,
                addFolder: { isPickingFolder = true },
                importFile: { isImporting = true },
                addCatalogue: { isAddingCatalogue = true },
                addKavita: { isAddingKavita = true },
                addShare: { isAddingShare = true }
            )
        }
    }
}
