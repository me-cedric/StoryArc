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

/// Which source the library is showing.
///
/// `library-browsing`: one library over every configured source, and a way to narrow it to
/// one. A menu rather than a row of chips, because the number of sources is the reader's
/// and a strip of six of them would take the space the artwork is for.
///
/// Absent with fewer than two sources: a selector offering "All sources" and the one source
/// there is asks a question with a single answer.
struct ScopeMenu: View {
    let model: LibraryModel

    var body: some View {
        Menu {
            Picker(selection: scopeBinding) {
                Text("library.scope.all", bundle: .module).tag(LibraryScope.allSources)
                ForEach(model.registry.sources) { source in
                    Text(source.displayName).tag(LibraryScope.source(source.id))
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
        .accessibilityValue(scopeName)
    }

    private var scopeBinding: Binding<LibraryScope> {
        Binding(get: { model.query.scope }, set: { model.query.scope = $0 })
    }

    private var scopeName: Text {
        guard let name = model.registry.name(of: model.query.scope.sourceID) else {
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
