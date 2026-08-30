public import SwiftUI

internal import DesignSystem
public import StoryArcCore

// The controls that narrow the library: layout, sorting, and what to say when they
// leave nothing on screen. Split out of `LibraryView` so the screen itself stays
// readable — the menus are half its length and none of their detail matters to the
// shape of the screen. Filtering left in turn, to `LibraryFilterMenu`, once it grew
// to seven groups.

/// Grid or list.
///
/// One button that shows the layout it would switch *to*, rather than a segmented
/// control that spends permanent space on a binary choice.
struct LayoutToggle: View {
    let model: LibraryModel

    var body: some View {
        Button {
            model.layout = model.layout == .grid ? .list : .grid
        } label: {
            Label {
                Text(
                    model.layout == .grid ? "library.layout.list" : "library.layout.grid",
                    bundle: .module
                )
            } icon: {
                Image(systemName: model.layout == .grid ? "list.bullet" : "square.grid.2x2")
            }
        }
    }
}

/// Which source the library is showing.
///
/// `library-browsing`: one library over every configured source, and a way to narrow it to
/// one. A menu rather than a row of chips, because the number of sources is the reader's
/// and a strip of six of them would take the space the artwork is for.
///
/// Absent with fewer than two sources: a selector offering "All sources" and the one source
/// there is asks a question with a single answer. ``offered(in:)`` is that rule, and
/// `LibraryToolbar` asks it rather than deciding again.
struct ScopeMenu: View {
    let model: LibraryModel

    /// The scopes worth putting in front of a reader, or nothing at all.
    ///
    /// Empty below two sources, which is what makes the control *absent* rather than
    /// present and pointless. Android gates its own selector on `attributesPublications`
    /// in `LibraryScreen.kt`; this is the same gate, and keeping it here — beside the menu
    /// it governs — is what lets the toolbar and this view agree without either restating
    /// the rule.
    ///
    /// The registry's own order, because ``SourceRegistry/scopes`` makes that order
    /// meaningful and a selector that reshuffled it would undo an arrangement the reader
    /// made by hand.
    static func offered(in registry: SourceRegistry) -> [LibraryScope] {
        registry.attributesPublications ? registry.scopes : []
    }

    var body: some View {
        Menu {
            Picker(selection: scopeBinding) {
                ForEach(Self.offered(in: model.registry), id: \.self) { scope in
                    name(of: scope).tag(scope)
                }
            } label: {
                Text("library.scope", bundle: .module)
            }
        } label: {
            Label {
                Text("library.scope", bundle: .module)
            } icon: {
                Image(
                    systemName: model.query.scope == .allSources
                        ? "square.stack.3d.up"
                        : "square.stack.3d.up.fill"
                )
            }
        }
        // Which source, spoken. The icon says that a scope is set and cannot say which one,
        // and DESIGN.md forbids a state carried by appearance alone.
        .accessibilityValue(name(of: model.query.scope))
    }

    private var scopeBinding: Binding<LibraryScope> {
        Binding(get: { model.query.scope }, set: { model.query.scope = $0 })
    }

    /// What one scope is called: the source's own name, or "All sources".
    ///
    /// One function for the row and for the spoken value, so the menu and VoiceOver can
    /// never name the same scope two different ways.
    private func name(of scope: LibraryScope) -> Text {
        guard let name = model.registry.name(of: scope.sourceID) else {
            return Text("library.scope.all", bundle: .module)
        }
        return Text(name)
    }
}

/// Why the results under it matched.
///
/// `library-browsing` asks for results "grouped by match kind — series, publication,
/// person, tag", which only means anything if the reader is told which group they are
/// looking at.
struct MatchHeading: View {
    @Environment(\.theme) private var theme

    let kind: MatchKind

    var body: some View {
        Text(kind.titleKey, bundle: .module)
            .textRole(.headline)
            .foregroundStyle(theme.palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.top, StoryArcSpace.md)
    }
}

/// How the library is ordered.
struct SortMenu: View {
    let model: LibraryModel

    var body: some View {
        Menu {
            Picker(selection: sortBinding) {
                ForEach(LibrarySort.allCases, id: \.self) { sort in
                    Text(sort.titleKey, bundle: .module).tag(sort)
                }
            } label: {
                Text("library.sort", bundle: .module)
            }

            Divider()

            Picker(selection: directionBinding) {
                Text("library.sort.ascending", bundle: .module).tag(true)
                Text("library.sort.descending", bundle: .module).tag(false)
            } label: {
                Text("library.sort.direction", bundle: .module)
            }
        } label: {
            Label {
                Text("library.sort", bundle: .module)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
    }

    private var sortBinding: Binding<LibrarySort> {
        Binding(get: { model.query.sort }, set: { model.query.sort = $0 })
    }

    private var directionBinding: Binding<Bool> {
        Binding(get: { model.query.ascending }, set: { model.query.ascending = $0 })
    }
}

/// What the reader searched for lately, under an open search field.
///
/// `library-browsing`: "when a user opens search, recent queries are offered, and
/// can be cleared". Offered only while nothing has been typed — once there is a
/// term, the results below the field are the better answer, and a list of old
/// searches sitting on top of them would hide what was just found.
struct RecentSearchSuggestions: View {
    let model: LibraryModel

    var body: some View {
        if model.query.search.trimmingCharacters(in: .whitespaces).isEmpty,
           !model.recentSearches.isEmpty {
            Section {
                ForEach(model.recentSearches.terms, id: \.self) { term in
                    // `searchCompletion` puts the term in the field, which runs the
                    // search: a recent query is a shortcut to the search, not to
                    // whatever it found last time.
                    Label {
                        Text(term)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .searchCompletion(term)
                }

                Button(role: .destructive) {
                    model.clearRecentSearches()
                } label: {
                    Text("library.search.recent.clear", bundle: .module)
                }
            } header: {
                Text("library.search.recent", bundle: .module)
            }
        }
    }
}
/// A library that has publications and is showing none of them.
struct NarrowedToNothing: View {
    @Environment(\.theme) private var theme

    let query: LibraryQuery
    let clear: () -> Void
    /// What the view is scoped to, when it is scoped to one source.
    var scopeName: String?
    /// Shows every source again. `nil` when the view is not scoped, so the offer is absent
    /// rather than present and pointless.
    var widen: (() -> Void)?

    var body: some View {
        VStack(spacing: StoryArcSpace.md) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.palette.textTertiary)

            message
                .textRole(.subheadline)
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)

            // `library-browsing`: a search that found nothing "offers to widen the scope to
            // all sources if the search was scoped". First, because it is the likelier of
            // the two — a reader who scoped to one server and typed a title usually wants
            // the rest of their library asked, not their filters undone.
            if let widen {
                Button(action: widen) {
                    Text("library.search.widen", bundle: .module)
                }
                .buttonStyle(.borderedProminent)
            }

            Button(action: clear) {
                Text("library.filter.clear", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, StoryArcSpace.gutter)
    }

    /// Names what was searched, which is what makes the state actionable rather
    /// than a shrug.
    ///
    /// Three sentences because there are three ways to arrive here, and a reader told
    /// "no publication matches the active filters" when they have set no filter at all
    /// goes looking for a filter that does not exist.
    private var message: Text {
        let term = query.search.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty {
            return Text("library.empty.search \(term)", bundle: .module)
        }
        if query.hasFilters {
            return Text("library.empty.filtered", bundle: .module)
        }
        if let scopeName {
            return Text("library.empty.scope \(scopeName)", bundle: .module)
        }
        return Text("library.empty.filtered", bundle: .module)
    }
}

/// The four ways to add somewhere to read from.
///
/// A menu rather than four buttons. There are four kinds of source now and there will be
/// more; a toolbar with one button per kind would crowd out the controls a reader uses
/// every day. Android's `AddSourceMenu` is the same menu.
///
/// Out of `LibraryView` for the reason the rest of this file is: the shape of the screen is
/// not what forty lines of labels and glyphs are about.
struct AddSourceMenu: View {
    let addFolder: () -> Void
    /// `local-library`: a file brought in from elsewhere is copied into storage the app
    /// owns. Its own control rather than a mode of "add a folder", because a reader adding
    /// a folder is pointing at something they keep, and a reader importing is handing it over.
    let importFile: () -> Void
    let addCatalogue: () -> Void
    let addKavita: () -> Void
    let addShare: () -> Void

    var body: some View {
        Menu {
            item("library.addFolder", "folder.badge.plus", addFolder)
            ImportPublicationButton(action: importFile)
            item("catalogue.title", "dot.radiowaves.up.forward", addCatalogue)
            item("kavita.title", "externaldrive.connected.to.line.below", addKavita)
            item("smb.title", "externaldrive.badge.wifi", addShare)
        } label: {
            Label {
                Text("library.addSource", bundle: .module)
            } icon: {
                Image(systemName: "plus")
            }
        }
    }

    @ViewBuilder
    private func item(
        _ key: LocalizedStringKey,
        _ symbol: String,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(key, bundle: .module)
            } icon: {
                Image(systemName: symbol)
            }
        }
    }
}
