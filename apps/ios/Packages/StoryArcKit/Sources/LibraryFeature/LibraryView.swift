public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// The library. At this stage it renders the empty state and the source list —
/// the two surfaces `sources` requires before any content exists.
///
/// Cover grid, search, filtering and sorting land with the `library-browsing`
/// capability; this is the shell they hang off.
public struct LibraryView: View {
    @Environment(\.theme) private var theme

    private let sources: [Source]

    public init(sources: [Source] = []) {
        self.sources = sources
    }

    public var body: some View {
        NavigationStack {
            Group {
                if sources.isEmpty {
                    EmptyLibraryView()
                } else {
                    SourceList(sources: sources)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.palette.surfaceCanvas)
            .navigationTitle(Text("library.title", bundle: .module))
        }
    }
}

/// `sources`: an empty library names the four source types with a one-line
/// explanation of each, and offers to open a file without configuring anything.
/// Never an illustration with no action — see DESIGN.md §9.
struct EmptyLibraryView: View {
    @Environment(\.theme) private var theme

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
