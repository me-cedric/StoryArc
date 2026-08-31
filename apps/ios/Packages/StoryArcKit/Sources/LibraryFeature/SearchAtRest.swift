internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The search screen with nothing typed into it yet.
///
/// `navigation-shell`'s *What search opens onto*: recent searches, and publications the
/// reader already has — one in progress, one never opened, one next in a series they have
/// read. ``SearchSuggestions`` is the arithmetic; this is the screen.
///
/// **Not `.searchSuggestions`, and that is the decision worth recording.** The modifier is
/// the obvious answer and was what this surface used: it is one line, and the platform draws
/// the list. What it draws is a list *attached to the field* — a dropdown over whatever is
/// behind it — and what the requirement asks for is a screen with headed sections a reader
/// can scroll through before deciding to type. Three shelves of covers do not belong in a
/// completion dropdown. So the screen draws them itself, and recent searches move down here
/// with them rather than living in a control that appears only while the field has focus.
///
/// What was underneath before was **the shelf** — the whole library grid, waiting to be
/// narrowed. That is what made search read as a filter over a shelf rather than as a place,
/// which is the thing `navigation-shell` was rewritten to stop.
struct SearchAtRest: View {
    @Environment(\.theme) private var theme

    let model: LibraryModel
    /// The five ways in, when there is nothing to suggest from. Passed through rather than
    /// rebuilt — see ``SearchNothingToSuggest``.
    let addFolder: () -> Void
    let importFile: () -> Void
    let addCatalogue: () -> Void
    let addKavita: () -> Void
    let addShare: () -> Void

    private var offer: SearchSuggestions {
        SearchSuggestions.of(model.publications) { model.record(of: $0) }
    }

    var body: some View {
        if offer.isEmpty && model.recentSearches.isEmpty {
            SearchNothingToSuggest(
                addFolder: addFolder,
                importFile: importFile,
                addCatalogue: addCatalogue,
                addKavita: addKavita,
                addShare: addShare
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                    if !model.recentSearches.isEmpty { recents }

                    // Each section is drawn only when it has something in it.
                    // `navigation-shell`: the screen "says so in one sentence rather than
                    // drawing empty headings", and a heading over nothing is the same
                    // mistake in miniature.
                    shelf(Text("search.suggestions.inProgress", bundle: .module), offer.inProgress)
                    shelf(Text("search.suggestions.nextInSeries", bundle: .module), offer.nextInSeries)
                    shelf(Text("search.suggestions.neverOpened", bundle: .module), offer.neverOpened)
                }
                .padding(.vertical, StoryArcSpace.lg)
            }
        }
    }

    /// One suggestion shelf, or nothing at all.
    @ViewBuilder
    private func shelf(_ title: Text, _ publications: [Publication]) -> some View {
        if !publications.isEmpty {
            VStack(alignment: .leading, spacing: StoryArcSpace.md) {
                title
                    .textRole(.title3)
                    .foregroundStyle(theme.palette.textPrimary)
                    .padding(.horizontal, StoryArcSpace.gutter)

                // The same run of covers Home draws, so a suggestion looks and behaves like
                // a cover everywhere else in the app and opens the same page.
                HomeShelfRow(publications: publications, model: model)
            }
        }
    }

    /// The reader's own earlier queries, and the one action that empties them.
    ///
    /// `library-browsing`: recent queries "are offered, and can be cleared". A term chosen
    /// here is written into the model's query, which is what the field is bound to — so it
    /// runs exactly as if it had been typed, rather than replaying whatever it found last
    /// time.
    private var recents: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            HStack {
                Text("library.search.recent", bundle: .module)
                    .textRole(.title3)
                    .foregroundStyle(theme.palette.textPrimary)

                Spacer(minLength: StoryArcSpace.md)

                Button(role: .destructive) {
                    model.clearRecentSearches()
                } label: {
                    Text("library.search.recent.clear", bundle: .module)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.palette.textSecondary)
            }
            .padding(.horizontal, StoryArcSpace.gutter)

            ForEach(model.recentSearches.terms, id: \.self) { term in
                Button {
                    model.query.search = term
                } label: {
                    Label {
                        Text(term)
                            .foregroundStyle(theme.palette.textPrimary)
                        Spacer(minLength: 0)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(theme.palette.textTertiary)
                    }
                    .contentShape(.rect)
                    .padding(.horizontal, StoryArcSpace.gutter)
                    .padding(.vertical, StoryArcSpace.xs)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The search screen when the library has nothing to suggest from.
///
/// `navigation-shell`'s *Nothing to suggest*: "the screen says so in one sentence rather than
/// drawing empty headings", and "it offers the same way of adding a source that the library's
/// own empty state offers".
///
/// The second half is taken literally: the action is ``AddSourceMenu``, the same control
/// ``EmptyLibraryView`` puts under the same situation one destination away — not a button
/// spelled the same way. There are four kinds of library and there will be more, and a second
/// menu written here is how one of them ends up a row short. `LibraryToolbar` did exactly
/// that, hand-building a four-item menu that omitted the import, and the only way a file
/// reached StoryArc on iOS was the system's Open-in handler.
///
/// The *sentence* is search's own. The library being empty and search having nothing to
/// suggest are the same cause and two different disappointments, and a reader on the search
/// page told "your library is empty" would be being answered about a screen they are not on.
struct SearchNothingToSuggest: View {
    let addFolder: () -> Void
    let importFile: () -> Void
    let addCatalogue: () -> Void
    let addKavita: () -> Void
    let addShare: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("search.empty.title", bundle: .module)
            } icon: {
                Image(systemName: "magnifyingglass")
            }
        } description: {
            Text("search.empty.subtitle", bundle: .module)
        } actions: {
            AddSourceMenu(
                addFolder: addFolder,
                importFile: importFile,
                addCatalogue: addCatalogue,
                addKavita: addKavita,
                addShare: addShare
            )
        }
        .frame(maxWidth: StoryArcSpace.huge * 8)
        // At the largest Dynamic Type size the sentence is taller than the screen, and
        // without somewhere to scroll the action sits behind the tab bar. `HomeEmpty` learned
        // this on the surface next door.
        .reachableAtEveryTextSize()
    }
}
