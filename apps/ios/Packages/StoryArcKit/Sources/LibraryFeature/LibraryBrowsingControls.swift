public import SwiftUI

internal import DesignSystem
public import StoryArcCore

// The controls that decide how the library is drawn, and what to say when they leave nothing
// on screen. Split out of `LibraryView` so the screen itself stays readable — the menus are
// half its length and none of their detail matters to the shape of the screen. Filtering left
// in turn, to `LibraryFilterMenu`, once it grew to seven groups; the recent searches and the
// add menu to files of their own, when each of them stopped being a declaration nobody could
// reach.
//
// It went the other way once. The availability selector had left to `ScopeMenu.swift` and has
// come back as a picker inside `ViewMenu`, along with the layout toggle — three toolbar items
// folded into one named menu, per `library-browsing`'s grouping rule. `LibraryAvailability.swift`
// is what that file is called now: the axis itself is still a value the whole module reads,
// and it was only ever the *control* that lived beside it.

/// Everything about *how the shelf is drawn*, under one name.
///
/// **This is three toolbar items that used to sit side by side.** The library's
/// `.primaryAction` held six controls, four of them an unlabelled glyph: a reader could not
/// tell the availability selector from the layout toggle from the sort without pressing one.
/// `library-browsing` now asks that "the choices — what is shown, how it is grouped, how it
/// is sorted, what is filtered out — are reached through named menus rather than as separate
/// unlabelled buttons", and this is the menu the first three of those reach.
///
/// **It was called `SortMenu`, and the name went with the contents.** A type and a label
/// reading *Sort* that also decide availability and layout is precisely the drift this
/// repository keeps paying for; the sort choices are still here, as their own named picker,
/// which is what "the sort menu stays" was asking for. `FilterMenu` is untouched — what is
/// filtered out is a different question from how the same set is drawn, and folding the two
/// together would have put seven filter groups and three view choices behind one word.
///
/// **Availability is here rather than in the filter menu, deliberately.** `library-browsing`
/// makes it the library's *primary axis* and ``ScopeMenu``'s successor comment argued the
/// distinction at length: narrowing to one library is a filter — counted in the badge,
/// cleared by *Clear filters* — and narrowing to what opens with no network is a mode the
/// shelf is in. Moving it into the filter menu would have made it a filter by placement while
/// every other line of this module still calls it an axis.
///
/// **The icon states the axis, because the control that used to state it is gone.**
/// `library-browsing` asks that the availability choice "persists until changed, **and is
/// visible while it is active**", and it was `ScopeMenu`'s own glyph that held that promise.
/// So this menu draws the platform's own view-options glyph while the shelf shows everything
/// and the availability symbol while it does not — the same trade ``FilterMenu`` makes with
/// its filled and unfilled variants, for the same requirement.
struct ViewMenu: View {
    let model: LibraryModel

    /// The primary axis, owned by the screen so it survives the menu closing.
    ///
    /// Handed in rather than read here for the reason ``LibraryAvailability`` gives: the
    /// query is the value both platforms encode and this is one iOS shelf choice with a
    /// `UserDefaults` key of its own.
    @Binding var availability: LibraryAvailability

    var body: some View {
        Menu {
            // First, because it is the only one of the three that changes *which*
            // publications are on the shelf. The two below change how the same set is drawn.
            Picker(selection: $availability) {
                ForEach(LibraryAvailability.allCases, id: \.self) { value in
                    Label {
                        Text(value.titleKey, bundle: .module)
                    } icon: {
                        Image(systemName: value.symbolName)
                    }
                    .tag(value)
                }
            } label: {
                Text("library.scope", bundle: .module)
            }

            Divider()

            // A picker rather than the toggling button this replaced. The button showed the
            // layout it would switch *to*, which is unreadable in a list of choices: a row
            // saying "List" beside a shelf drawn as a grid states neither where the reader
            // is nor where they would go.
            Picker(selection: layoutBinding) {
                Text("library.layout.grid", bundle: .module).tag(LibraryLayout.grid)
                Text("library.layout.list", bundle: .module).tag(LibraryLayout.list)
            } label: {
                Text("library.layout", bundle: .module)
            }

            Divider()

            Picker(selection: sortBinding) {
                ForEach(LibrarySort.allCases, id: \.self) { sort in
                    Text(sort.titleKey, bundle: .module).tag(sort)
                }
            } label: {
                Text("library.sort", bundle: .module)
            }

            Picker(selection: directionBinding) {
                Text("library.sort.ascending", bundle: .module).tag(true)
                Text("library.sort.descending", bundle: .module).tag(false)
            } label: {
                Text("library.sort.direction", bundle: .module)
            }
        } label: {
            Label {
                Text("library.view", bundle: .module)
            } icon: {
                Image(
                    systemName: availability == .everywhere
                        ? "ellipsis.circle"
                        : availability.symbolName
                )
            }
        }
        // What the shelf is narrowed to, spoken. The icon says that a narrowing is set and
        // cannot say which one, and design.md forbids a state carried by appearance alone.
        .accessibilityValue(Text(availability.titleKey, bundle: .module))
    }

    private var layoutBinding: Binding<LibraryLayout> {
        Binding(get: { model.layout }, set: { model.layout = $0 })
    }

    private var sortBinding: Binding<LibrarySort> {
        Binding(get: { model.query.sort }, set: { model.query.sort = $0 })
    }

    private var directionBinding: Binding<Bool> {
        Binding(get: { model.query.ascending }, set: { model.query.ascending = $0 })
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
            // shelf to what is on this device and found nothing usually wants that lifted,
            // not their filters cleared.
            //
            // One label, because there is now one thing this widens. It used to fall through
            // to widening a *scope* to every source; that narrowing is a filter now and the
            // button below is what undoes it.
            if let widen {
                Button(action: widen) {
                    Text("library.availability.widen", bundle: .module)
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
