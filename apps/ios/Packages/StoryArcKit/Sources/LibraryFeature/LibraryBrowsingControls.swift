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
