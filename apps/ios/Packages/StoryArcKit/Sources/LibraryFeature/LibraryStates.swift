public import SwiftUI

internal import DesignSystem
public import StoryArcCore

// What the library shows before it shows publications: a scan in progress, a
// summary of what it skipped, the empty state, and the source list. Split out of
// `LibraryView` for the same reason as the controls.

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
            .storyArcGlass(in: Rectangle())
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

    /// The other kinds that are built. Nil for a kind that is not, which is what keeps a
    /// row from looking like a button that does nothing.
    var addCatalogue: (() -> Void)?
    var addKavita: (() -> Void)?

    /// What tapping a kind does, when that kind exists.
    ///
    /// The rows describe every source `sources` specifies, and two of the four are built.
    /// A row with no action stays a description — the alternative is four identical rows of
    /// which two do nothing, which is worse than saying less.
    private func action(for kind: SourceKind) -> (() -> Void)? {
        switch kind {
        case .localFolder: addFolder
        case .opdsCatalog: addCatalogue
        case .kavitaServer: addKavita
        case .networkShare: nil
        }
    }

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
                    SourceKindRow(kind: kind, action: action(for: kind))
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

    /// Nil for a kind that is described but not built.
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
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

            // The affordance, only where there is something to tap. Two rows that look
            // identical and behave differently is the defect this avoids.
            if action != nil {
                Image(systemName: "chevron.right")
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
            }
        }
        .padding(StoryArcSpace.md)
        .frame(minHeight: StoryArcSpace.xxl + StoryArcSpace.md)
        .background(theme.palette.surfaceRaised, in: .rect(cornerRadius: StoryArcRadius.lg))
    }
}

struct SourceList: View {
    @Environment(\.theme) private var theme

    let sources: [Source]
    /// How many publications each source holds, for the removal statement.
    var itemCount: (Source.ID) -> Int = { _ in 0 }
    var onRemove: ((Source) -> Void)?

    /// Which source a confirmation is open for.
    @State private var removing: Source?

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
                .swipeActions(edge: .trailing) {
                    if onRemove != nil {
                        Button(role: .destructive) { removing = source } label: {
                            Text("source.remove", bundle: .module)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            Text("source.remove.title \(removing?.displayName ?? "")", bundle: .module),
            isPresented: Binding(
                get: { removing != nil },
                set: { if !$0 { removing = nil } }
            ),
            titleVisibility: .visible,
            presenting: removing
        ) { source in
            Button(role: .destructive) {
                onRemove?(source)
                removing = nil
            } label: {
                Text("source.remove", bundle: .module)
            }
        } message: { source in
            // `sources` asks the app to state "how many downloaded files and how much disk
            // space will be freed before asking for confirmation". For a folder the honest
            // answer is none and nothing, and saying so is the whole point: a reader must
            // not have to guess whether this deletes their comics.
            Text("source.remove.body \(itemCount(source.id))", bundle: .module)
        }
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
        .storyArcGlass(in: Rectangle())
    }
}
