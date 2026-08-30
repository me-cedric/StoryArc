public import SwiftUI

internal import DesignSystem
public import StoryArcCore

// The controls that narrow the library: layout, sorting, and what to say when they leave
// nothing on screen. Split out of `LibraryView` so the screen itself stays readable — the
// menus are half its length and none of their detail matters to the shape of the screen.
// Filtering left in turn, to `LibraryFilterMenu`, once it grew to seven groups; the
// availability selector left to `ScopeMenu.swift`, the recent searches and the add menu to
// files of their own, when each of them stopped being a declaration nobody could reach.

/// Grid or list.
///
/// One button that shows the layout it would switch *to*, rather than a segmented control
/// that spends permanent space on a binary choice.
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

/// Why the results under it matched.
///
/// `library-browsing` asks for results "grouped by match kind — series, publication, person,
/// tag", which only means anything if the reader is told which group they are looking at.
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

/// A library that has publications and is showing none of them.
struct NarrowedToNothing: View {
    @Environment(\.theme) private var theme

    let query: LibraryQuery
    let clear: () -> Void
    /// What the view is narrowed to, when it is narrowed to one library.
    var scopeName: String?
    /// Whether the shelf is showing only what is on this device.
    ///
    /// Its own flag rather than another string, because it changes both sentences: what is
    /// hiding the library, and what the button above the filters offers to undo.
    var isNarrowedToDevice = false
    /// Widens the shelf again. `nil` when there is nowhere wider to go, so the offer is
    /// absent rather than present and pointless.
    var widen: (() -> Void)?

    var body: some View {
        VStack(spacing: StoryArcSpace.md) {
            Image(systemName: isNarrowedToDevice
                ? "arrow.down.circle"
                : "line.3.horizontal.decrease.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.palette.textTertiary)

            message
                .textRole(.subheadline)
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)

            // The likelier of the two undos, so it comes first: a reader who narrowed the
            // shelf and found nothing usually wants the narrowing lifted, not their filters
            // cleared.
            if let widen {
                Button(action: widen) {
                    Text(
                        isNarrowedToDevice ? "library.availability.widen" : "library.search.widen",
                        bundle: .module
                    )
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

    /// Names what is narrowing the shelf, which is what makes the state actionable rather
    /// than a shrug.
    ///
    /// Four sentences because there are four ways to arrive here, and a reader told "nothing
    /// matches the filters you set" when they have set no filter at all goes looking for a
    /// filter that does not exist.
    private var message: Text {
        let term = query.search.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty {
            return Text("library.empty.search \(term)", bundle: .module)
        }
        if isNarrowedToDevice {
            return Text("library.empty.onDevice", bundle: .module)
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
