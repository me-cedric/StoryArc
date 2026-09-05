public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// A secondary place the sidebar can send a reader.
///
/// Secondary is the whole of it. `navigation-shell` fixes the destination set at three and
/// says the wide window "SHALL become the platform's own wide-window navigation without
/// becoming a different set" — so nothing here is a destination, and none of it appears in
/// the tab bar. These are *sections of the one library* and *the reader's own shelves*,
/// which is the second half of the same requirement, and the reason a shelf can be reached
/// in one tap on an iPad without the phone growing a fourth tab.
///
/// **No case is a source.** That is the sentence the requirement repeats three times, and
/// it is what tells this apart from the `SidebarDestination` the shell replaced: a reader
/// with four servers got four navigation rows and their own navigation said *Kavita* to
/// them. A reader with four servers gets exactly these rows.
public enum SidebarEntry: Hashable, Sendable {
    /// What arrived lately, over every source at once.
    case recentlyAdded
    /// The library grouped by what a reader recognises before an issue title.
    case series
    /// Every collection and reading list — the route that makes the overflow reachable
    /// however many shelves a reader has.
    case allShelves
    case collection(UUID)
    case list(UUID)
}

/// How wide text is allowed to get before the window stops composing it.
///
/// §3.11 asks for a `maxContentWidth` "so text does not run to 13 inches". On a 13-inch
/// iPad an unconstrained description runs to nearly two hundred characters a line and a
/// primary action becomes a metre-wide bar — both of which are a page *filling* a window
/// rather than using it. Wider than a pure reading column because a shelf of covers lives
/// inside the same measure on the detail page.
///
/// Deliberately **not** applied to a horizontal shelf. §3.11 is explicit that shelves
/// "touch the leading and trailing edges so the system scrolls them under the sidebar
/// automatically" — a shelf pulled into this column would sit in a box in the middle of the
/// window, which is the layout this slice exists to end.
///
/// It lives here rather than in `DesignSystem` only because this slice does not own that
/// file; it belongs beside ``StoryArcWindowClass/sidebarWidthThreshold``, and the handoff
/// says so.
enum SidebarLayout {
    /// ``StoryArcWindowClass/maxContentWidth``, which is where this now lives — beside the
    /// threshold it belongs next to, and inside the module `SettingsFeature` can reach.
    /// Kept as a name here so the four call sites in this module still read as layout rather
    /// than as a window class, and so that one number remains one number.
    static let maxContentWidth: CGFloat = StoryArcWindowClass.maxContentWidth
}

/// The iPad sidebar's own rows: library sections, then the reader's shelves.
///
/// Dropped into the shell's `TabView` beside the three destinations, and **hidden from the
/// tab bar** with `defaultVisibility(.hidden, for: .tabBar)`. That modifier is the whole
/// reason this can exist without touching the phone: `.sidebarAdaptable` renders one set
/// two ways, and without it every row below would land in a compact tab bar that
/// `navigation-shell` caps at three destinations plus the search role — pushing the three
/// into an overflow that the same requirement forbids.
///
/// The sections follow the Apple Music sidebar the owner sent, which is also what §3.11
/// asks for: a **Library** header over sections of the one library, then a **Shelves**
/// header over what the reader made. Settings stays in the toolbar, outside the selection,
/// as it already is.
public struct LibrarySidebar<Value: Hashable>: TabContent {
    /// Whether this window has a sidebar to put the sections in.
    ///
    /// The gate, and it is load-bearing rather than tidy. `defaultVisibility(.hidden, for:
    /// .tabBar)` alone was not enough: it governs the iPad's own tab bar, and a **compact**
    /// window has a different bar that folds every section it is given into a *More* tab.
    /// On an iPhone that is `navigation-shell`'s forbidden outcome measured exactly — the
    /// three destinations "displaced or pushed out of reach" by secondary entries — and it
    /// was visible on a booted iPhone 17 Pro before this gate existed: Home · Library ·
    /// Downloads · **More** · search.
    ///
    /// So the sections are not merely hidden in a compact window; they are not there. A
    /// window with no sidebar has nowhere to put them, and the rows they lead to are all
    /// reachable from Home in a phone's own navigation.
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let model: LibraryModel
    private let onOpen: (Publication, URL) -> Void
    /// How a sidebar entry is spelled in the shell's own selection type.
    ///
    /// A closure rather than a shared enum, so the shell keeps one selection type and this
    /// file needs to know nothing about it.
    private let value: (SidebarEntry) -> Value

    public init(
        model: LibraryModel,
        onOpen: @escaping (Publication, URL) -> Void,
        value: @escaping (SidebarEntry) -> Value
    ) {
        self.model = model
        self.onOpen = onOpen
        self.value = value
    }

    /// The shelves listed inline, longest-lived first.
    ///
    /// Capped, and the cap is not a truncation: whatever does not fit is behind *All
    /// shelves* at the foot of the same section, which is what `navigation-shell` means by
    /// "the overflow is reachable within the navigation itself". The three destinations
    /// cannot be displaced by a reader with forty collections.
    private static var inlineShelfLimit: Int { 8 }

    public var body: some TabContent<Value> {
        if sizeClass == .regular {
            sections
        }
    }

    @TabContentBuilder<Value>
    private var sections: some TabContent<Value> {
        TabSection {
            Tab(value: value(.recentlyAdded)) {
                NavigationStack {
                    HomeMore(
                        title: Text("home.recentlyAdded", bundle: .module),
                        publications: HomeShelves.recentlyAdded(in: model.publications, limit: .max),
                        model: model
                    )
                    .publicationPages(in: model, onOpen: onOpen)
                }
            } label: {
                Label {
                    Text("home.recentlyAdded", bundle: .module)
                } icon: {
                    Image(systemName: "clock")
                }
            }

            Tab(value: value(.series)) {
                NavigationStack {
                    SidebarSeriesList(model: model)
                        .publicationPages(in: model, onOpen: onOpen)
                }
            } label: {
                Label {
                    Text("library.match.series", bundle: .module)
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                }
            }
        } header: {
            Text("sidebar.library", bundle: .module)
        }
        .defaultVisibility(.hidden, for: .tabBar)

        TabSection {
            ForEach(model.shelves.collections.prefix(Self.inlineShelfLimit)) { collection in
                Tab(value: value(.collection(collection.id))) {
                    NavigationStack {
                        CollectionDetail(model: model, id: collection.id)
                            .publicationPages(in: model, onOpen: onOpen)
                    }
                } label: {
                    Label {
                        Text(collection.name)
                    } icon: {
                        Image(systemName: "square.stack")
                    }
                }
            }

            ForEach(model.shelves.lists.prefix(Self.inlineShelfLimit)) { list in
                Tab(value: value(.list(list.id))) {
                    NavigationStack {
                        ReadingListDetail(model: model, id: list.id)
                    }
                } label: {
                    Label {
                        Text(list.name)
                    } icon: {
                        Image(systemName: "list.bullet")
                    }
                }
            }

            // Always present, never conditional on the cap. It is the way to make a shelf
            // as well as the way to the ones that did not fit, and a reader with none at
            // all needs it most.
            Tab(value: value(.allShelves)) {
                NavigationStack {
                    ShelvesView(model: model, onOpen: onOpen)
                        .publicationPages(in: model, onOpen: onOpen)
                }
            } label: {
                Label {
                    Text("sidebar.allShelves", bundle: .module)
                } icon: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        } header: {
            Text("shelves.title", bundle: .module)
        }
        .defaultVisibility(.hidden, for: .tabBar)
    }

    // No `open(_:)`. Every row here leads to a grid or a list of covers, and a cover leads
    // to the publication's page; the page is what reaches the reader, through `onOpen`
    // handed to each stack's `publicationPages(in:onOpen:)`. The reading list is the one
    // exception and it is not a cover surface — see ``ReadingListDetail``.
}

/// The library as its series, for the sidebar's *Series* row.
///
/// A list of names rather than a second grid of covers: the question this row answers is
/// *what runs do I have*, and a wall of issue covers answers *what issues do I have*, which
/// is the Library destination's job. Choosing one leads to the same grid every other shelf
/// leads to, filtered to that series — so a reader learns the screen once.
///
/// Unattributed publications are absent rather than gathered under a heading of their own.
/// A folder library is mostly loose files, and *Uncategorised (412)* at the top of this list
/// would be the list.
struct SidebarSeriesList: View {
    @Environment(\.theme) private var theme

    let model: LibraryModel

    /// Every series in the library, in the order a reader reads names.
    ///
    /// `localizedStandardCompare` rather than `<`, for the reason ``DetailSeriesShelf``
    /// gives about issue numbers: a plain string comparison sorts by code point, which puts
    /// "Ändern" after "Zephyr" in German and is wrong in every language that has an accent.
    private var series: [(name: String, issues: [Publication])] {
        Dictionary(grouping: model.publications.filter { !($0.series ?? "").isEmpty }) {
            $0.series ?? ""
        }
        .map { (name: $0.key, issues: $0.value) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let series = series

        Group {
            if series.isEmpty {
                // The same shape `home-screen` uses: one sentence, and no heading over a
                // gap. A library with no series is a normal library, not a fault.
                ContentUnavailableView {
                    Text("library.match.series", bundle: .module)
                } description: {
                    Text("sidebar.series.empty", bundle: .module)
                }
                // Centred on its own, because the frame below leaves the *list* at the
                // leading edge and a sentence pinned to the top-left corner of a 13-inch
                // window is not an empty state, it is a stray line.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // A `ScrollView` of rows rather than a `List`, and the reason is the measure.
                // A plain `List` paints its own rows in the system's white; constrained to
                // the measure on a 13-inch window that leaves a hard vertical seam down the
                // middle, white inside the column and the app's canvas outside it — a screen
                // that looks like it failed to finish drawing. `scrollContentBackground` does
                // not reach the row backgrounds. Every other surface in this app composes its
                // rows this way for the same reason.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(series, id: \.name) { entry in
                            row(entry)
                        }
                    }
                    // The measure, and this screen needed it as much as Home did:
                    // unconstrained, every row put its chevron a foot from the name it
                    // belonged to, which is the defect this slice exists to end. Leading
                    // rather than centred, so the names start on the same gutter every other
                    // surface starts on.
                    .frame(maxWidth: SidebarLayout.maxContentWidth, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.surfaceCanvas)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle(Text("library.match.series", bundle: .module))
    }

    /// One series, and the way into it.
    ///
    /// The rule under the row rather than around it, so a run of them reads as a list
    /// without either a card each or a box round the lot.
    private func row(_ entry: (name: String, issues: [Publication])) -> some View {
        NavigationLink {
            HomeMore(title: Text(entry.name), publications: entry.issues, model: model)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: StoryArcSpace.sm) {
                    Text(entry.name)
                        .textRole(.body)
                        .foregroundStyle(theme.palette.textPrimary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: StoryArcSpace.md)

                    Image(systemName: "chevron.right")
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textTertiary)
                }
                .padding(.horizontal, StoryArcSpace.gutter)
                .frame(minHeight: StoryArcSpace.xxl)

                Rectangle()
                    .fill(theme.palette.borderSubtle)
                    .frame(height: 1)
                    .padding(.leading, StoryArcSpace.gutter)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
