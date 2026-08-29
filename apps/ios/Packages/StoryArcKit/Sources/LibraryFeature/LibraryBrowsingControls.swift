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

    var body: some View {
        VStack(spacing: StoryArcSpace.md) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.palette.textTertiary)

            message
                .textRole(.subheadline)
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: clear) {
                Text("library.filter.clear", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, StoryArcSpace.gutter)
    }

    /// Names what was searched, which is what makes the state actionable rather
    /// than a shrug.
    private var message: Text {
        let term = query.search.trimmingCharacters(in: .whitespaces)
        if term.isEmpty {
            return Text("library.empty.filtered", bundle: .module)
        }
        return Text("library.empty.search \(term)", bundle: .module)
    }
}
