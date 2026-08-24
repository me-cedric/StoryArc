public import SwiftUI

internal import DesignSystem
internal import UniformTypeIdentifiers
public import StoryArcCore

/// The library.
///
/// Three states, in the order a user meets them: nothing added, a scan running,
/// and a grid of covers. Search, filtering and sorting are the rest of
/// `library-browsing` and are not here yet.
public struct LibraryView: View {
    @Environment(\.theme) private var theme
    @State private var model = LibraryModel()
    @State private var isPickingFolder = false

    private let sources: [Source]
    private let onOpen: (Publication, URL) -> Void

    /// `onOpen` is how the app layer reaches the reader. The library knows which
    /// publication was chosen and where it lives; it does not know what a reader
    /// is.
    public init(
        sources: [Source] = [],
        onOpen: @escaping (Publication, URL) -> Void = { _, _ in }
    ) {
        self.sources = sources
        self.onOpen = onOpen
    }

    public var body: some View {
        NavigationStack {
            Group {
                if !model.publications.isEmpty {
                    CoverGrid(publications: model.publications, model: model) { publication in
                        if let url = model.location(of: publication) {
                            onOpen(publication, url)
                        }
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
            .toolbar {
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
                if case let .finished(found, skipped) = model.scanState, skipped > 0 {
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
