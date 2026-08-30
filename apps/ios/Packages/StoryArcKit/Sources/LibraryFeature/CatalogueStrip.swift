public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// The catalogues a reader has added, as a row of ways in.
///
/// A strip rather than a list: most readers have none or one, and a full-width section for
/// a single row would push the library down for everybody. It scrolls horizontally for the
/// reader who collects them.
struct CatalogueStrip: View {
    @Environment(\.theme) private var theme

    let sources: [Source]
    let onOpen: (Source) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: StoryArcSpace.sm) {
                ForEach(sources) { source in
                    Button {
                        onOpen(source)
                    } label: {
                        HStack(spacing: StoryArcSpace.xs) {
                            Image(systemName: source.kind.symbolName)
                                .foregroundStyle(theme.accent)

                            Text(source.displayName)
                                .textRole(.subheadline)
                                .foregroundStyle(theme.palette.textPrimary)
                                .lineLimit(1)

                            Image(systemName: "chevron.right")
                                .textRole(.caption)
                                .foregroundStyle(theme.palette.textTertiary)
                        }
                        .padding(.horizontal, StoryArcSpace.md)
                        .padding(.vertical, StoryArcSpace.sm)
                        // 44pt is the floor Apple's own audit checks, and a chip is the
                        // control most likely to fall under it.
                        .frame(minHeight: StoryArcSpace.xxl)
                        .background(theme.palette.surfaceRaised, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("catalogue.strip.hint", bundle: .module))
                }
            }
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.vertical, StoryArcSpace.sm)
        }
        .scrollIndicators(.hidden)
        // Liquid Glass rather than `.bar`. `native-experience` asks for floating chrome
        // on glass "with an opaque fallback declared for Reduce Transparency", and a
        // plain material gives neither: it does not pick up the covers moving beneath
        // it, and it has no fallback of its own to declare. The strip is carried as a
        // `safeAreaBar` by the library, so the content behind it fades at the boundary
        // rather than sliding under a hard edge.
        .storyArcGlass(in: Rectangle())
    }
}
