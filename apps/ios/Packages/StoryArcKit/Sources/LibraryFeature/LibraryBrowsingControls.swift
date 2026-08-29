public import SwiftUI

internal import DesignSystem
public import StoryArcCore

// The controls that narrow the library: layout, sorting, filtering, and what to
// say when they leave nothing on screen. Split out of `LibraryView` so the screen
// itself stays readable — the menus are half its length and none of their detail
// matters to the shape of the screen.

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

/// What the library is narrowed to.
///
/// `library-browsing`: filters combine with AND, the active count is visible on
/// the control, and one action clears them all.
struct FilterMenu: View {
    let model: LibraryModel

    var body: some View {
        Menu {
            Section {
                ForEach(ReadState.allCases, id: \.self) { state in
                    Toggle(isOn: readState(state)) {
                        Text(state.titleKey, bundle: .module)
                    }
                }
            } header: {
                Text("library.filter.readState", bundle: .module)
            }

            Section {
                ForEach(model.availableFormats, id: \.self) { value in
                    Toggle(isOn: binding(for: value)) { Text(value.displayName) }
                }
            } header: {
                Text("library.filter.format", bundle: .module)
            }

            if model.query.hasFilters {
                Divider()
                Button(role: .destructive) {
                    model.clearFilters()
                } label: {
                    Text("library.filter.clear", bundle: .module)
                }
            }
        } label: {
            Label {
                Text("library.filter", bundle: .module)
            } icon: {
                Image(
                    systemName: model.query.hasFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
        }
        // The count, spoken rather than drawn as a badge a menu label cannot carry.
        .accessibilityValue(
            model.query.hasFilters
                ? Text("library.filter.active \(model.query.activeFilterCount)", bundle: .module)
                : Text(verbatim: "")
        )
    }

    private func readState(_ state: ReadState) -> Binding<Bool> {
        Binding(
            get: { model.query.readStates.contains(state) },
            set: { on in
                if on { model.query.readStates.insert(state) } else { model.query.readStates.remove(state) }
            }
        )
    }

    private func binding(for value: PublicationFormat) -> Binding<Bool> {
        Binding(
            get: { model.query.formats.contains(value) },
            set: { on in
                if on { model.query.formats.insert(value) } else { model.query.formats.remove(value) }
            }
        )
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
    let addCatalogue: () -> Void
    let addKavita: () -> Void
    let addShare: () -> Void

    var body: some View {
        Menu {
            item("library.addFolder", "folder.badge.plus", addFolder)
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
