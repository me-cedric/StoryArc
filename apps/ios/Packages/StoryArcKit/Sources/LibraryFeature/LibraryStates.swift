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
