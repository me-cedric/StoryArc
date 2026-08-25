public import SwiftUI

internal import DesignSystem
public import Persistence
internal import UniformTypeIdentifiers
public import StoryArcCore

/// The library.
///
/// Three states, in the order a user meets them: nothing added, a scan running,
/// and a grid of covers, with search, filtering and sorting over the last of
/// them.
public struct LibraryView: View {
    @Environment(\.theme) private var theme
    @State private var isPickingFolder = false
    /// Owned by the app layer, not by this view.
    ///
    /// The app is what knows the reader was just dismissed, and a `.task` on this
    /// view does not fire again when a full-screen cover goes away — so the
    /// progress bars under the covers never updated. Whoever can observe the
    /// return has to be the one holding the model.
    private let model: LibraryModel

    private let sources: [Source]
    private let onOpen: (Publication, URL) -> Void
    private let progress: ProgressStore?

    /// `onOpen` is how the app layer reaches the reader. The library knows which
    /// publication was chosen and where it lives; it does not know what a reader
    /// is.
    public init(
        model: LibraryModel,
        sources: [Source] = [],
        progress: ProgressStore? = nil,
        onOpen: @escaping (Publication, URL) -> Void = { _, _ in }
    ) {
        self.model = model
        self.sources = sources
        self.progress = progress
        self.onOpen = onOpen
    }

    /// The search text, written straight through to the query.
    ///
    /// `@Bindable` on the model would be the idiomatic shape, and it cannot be
    /// used here: the model is a `let` owned by the app layer, not state this view
    /// creates. A binding does the same job without pretending otherwise.
    private var searchBinding: Binding<String> {
        Binding(get: { model.query.search }, set: { model.query.search = $0 })
    }

    /// Where a publication lives, handed to the app layer.
    private func open(_ publication: Publication) {
        if let url = model.location(of: publication) { onOpen(publication, url) }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if !model.visible.isEmpty {
                    if model.layout == .grid {
                        CoverGrid(
                            publications: model.visible,
                            // Hidden while a search or filter is running: the row
                            // is a shortcut to what you were reading, and showing
                            // publications the query excluded reads as a bug.
                            continueReading: model.query.isNarrowed ? [] : model.continueReading,
                            model: model,
                            onOpen: open
                        )
                    } else {
                        CoverList(publications: model.visible, model: model, onOpen: open)
                    }
                } else if !model.publications.isEmpty {
                    // A library that is not empty but looks it. `library-browsing`
                    // forbids showing that silently: say what is narrowing it and
                    // offer one action to undo.
                    NarrowedToNothing(query: model.query) {
                        model.clearFilters()
                        model.query.search = ""
                    }
                } else if case .scanning = model.scanState {
                    ScanningView(state: model.scanState)
                } else if sources.isEmpty {
                    EmptyLibraryView { isPickingFolder = true }
                } else {
                    SourceList(sources: sources)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.palette.surfaceCanvas)
            .navigationTitle(Text("library.title", bundle: .module))
            // `library-browsing`: results update as the user types, debounced, with
            // no submit action. SwiftUI's own field already debounces per keystroke
            // through the binding, and the arrange is a sort of what is in memory.
            .searchable(
                text: searchBinding,
                prompt: Text("library.search.prompt", bundle: .module)
            )
            // Reloaded on every appearance, which is what makes the bar under a
            // cover reflect the page the reader just reached.
            .task {
                model.restoreFolders()
                await model.refreshProgress()
            }
            .toolbar {
                if !model.publications.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        LayoutToggle(model: model)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        SortMenu(model: model)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        FilterMenu(model: model)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPickingFolder = true
                    } label: {
                        Label {
                            Text("library.addFolder", bundle: .module)
                        } icon: {
                            Image(systemName: "folder.badge.plus")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let missing = model.unavailableFolders.first {
                    // Named, per `local-library`. "A folder is no longer available"
                    // sends someone hunting through four of them.
                    UnavailableFolderNotice(name: missing) { isPickingFolder = true }
                } else if case let .finished(found, skipped) = model.scanState, skipped > 0 {
                    // Stated once, at the end, rather than per file — a messy
                    // folder would otherwise be a wall of notices. But stated:
                    // a count that silently omits what it could not read is a lie.
                    ScanSummary(found: found, skipped: skipped)
                }
            }
        }
        // `local-library`: a folder picked here is reachable again after a restart,
        // which is what the security-scoped bookmark in the model is for.
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let folder = urls.first {
                model.addFolder(folder)
            }
        }
    }
}

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

/// While a scan runs.
///
/// `local-library` requires progress reported as a count of items found, and
/// requires that browsing what is already found is not blocked — so this is only
/// ever seen before the first publication arrives.
struct ScanningView: View {
    @Environment(\.theme) private var theme

    let state: LibraryScanState

    var body: some View {
        VStack(spacing: StoryArcSpace.md) {
            ProgressView()
            if case let .scanning(found) = state {
                Text("library.scanning \(found)", bundle: .module)
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textSecondary)
                    .monospacedDigit()
            }
        }
    }
}

/// What a finished scan could not read.
struct ScanSummary: View {
    @Environment(\.theme) private var theme

    let found: Int
    let skipped: Int

    var body: some View {
        Text("library.skipped \(skipped)", bundle: .module)
            .textRole(.footnote)
            .foregroundStyle(theme.palette.textTertiary)
            .padding(.vertical, StoryArcSpace.sm)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
    }
}

/// `sources`: an empty library names the four source types with a one-line
/// explanation of each, and offers to open a file without configuring anything.
/// Never an illustration with no action — see DESIGN.md §9.
struct EmptyLibraryView: View {
    @Environment(\.theme) private var theme

    /// Offered here as well as in the toolbar. `sources` requires the empty state
    /// to offer an action rather than only describe one — see DESIGN.md §9.
    var addFolder: () -> Void = {}

    var body: some View {
        VStack(spacing: StoryArcSpace.xl) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(theme.palette.textTertiary)

            VStack(spacing: StoryArcSpace.sm) {
                Text("library.empty.title", bundle: .module)
                    .textRole(.title2)
                    .foregroundStyle(theme.palette.textPrimary)

                Text("library.empty.subtitle", bundle: .module)
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: StoryArcSpace.sm) {
                ForEach(SourceKind.allCases, id: \.self) { kind in
                    SourceKindRow(kind: kind)
                }
            }
            .padding(.top, StoryArcSpace.xs)

            Button(action: addFolder) {
                Label {
                    Text("library.addFolder", bundle: .module)
                } icon: {
                    Image(systemName: "folder.badge.plus")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, StoryArcSpace.sm)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .frame(maxWidth: StoryArcSpace.huge * 8)
    }
}

struct SourceKindRow: View {
    @Environment(\.theme) private var theme

    let kind: SourceKind

    var body: some View {
        HStack(spacing: StoryArcSpace.md) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 18))
                .foregroundStyle(theme.accent)
                .frame(width: StoryArcSpace.xl)

            // Tight stack: title and explanation read as one object, per the
            // uneven-rhythm rule in DESIGN.md §4.
            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(kind.titleKey, bundle: .module)
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textPrimary)
                Text(kind.explanationKey, bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(StoryArcSpace.md)
        .frame(minHeight: StoryArcSpace.xxl + StoryArcSpace.md)
        .background(theme.palette.surfaceRaised, in: .rect(cornerRadius: StoryArcRadius.lg))
    }
}

struct SourceList: View {
    @Environment(\.theme) private var theme

    let sources: [Source]

    var body: some View {
        List {
            ForEach(sources) { source in
                HStack(spacing: StoryArcSpace.md) {
                    Image(systemName: source.kind.symbolName)
                        .foregroundStyle(theme.accent)

                    VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                        Text(source.displayName)
                            .textRole(.body)
                            .foregroundStyle(theme.palette.textPrimary)
                        Text(source.state.statusKey, bundle: .module)
                            .textRole(.footnote)
                            .foregroundStyle(theme.palette.textTertiary)
                    }

                    Spacer(minLength: 0)

                    // Colour is never the only signal: the state is spelled out
                    // in the row above as well as carried by this dot.
                    Circle()
                        .fill(source.state.indicatorColor(theme.palette))
                        .frame(width: StoryArcSpace.sm, height: StoryArcSpace.sm)
                }
                // An offline source is dimmed, never reddened — offline is normal.
                .opacity(source.state.canFetch ? 1 : 0.55)
                .listRowBackground(theme.palette.surfaceRaised)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

/// A folder that was remembered and can no longer be read.
///
/// `local-library`: "the source is marked `unauthorized` with a plain-language
/// explanation naming the folder", and "a single action re-picks the folder,
/// preserving reading progress for everything inside it". Progress survives
/// because ADR-0006 keys it on the publication, not on the folder.
struct UnavailableFolderNotice: View {
    @Environment(\.theme) private var theme

    let name: String
    let repick: () -> Void

    var body: some View {
        HStack(spacing: StoryArcSpace.sm) {
            Text("library.folderUnavailable \(name)", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)

            Spacer(minLength: 0)

            Button(action: repick) {
                Text("library.repick", bundle: .module)
                    .textRole(.footnote)
            }
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.sm)
        .background(.thinMaterial)
    }
}
