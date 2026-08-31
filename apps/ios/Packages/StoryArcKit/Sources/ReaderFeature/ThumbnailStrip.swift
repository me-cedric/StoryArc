public import SwiftUI

internal import DesignSystem

/// Every page, small, in a row.
///
/// `comic-reader`: "every page is shown in a scrollable strip with the current page
/// marked, and tapping one jumps to it".
///
/// Lazy, and it has to be: a 300-page comic's strip would otherwise read 300
/// archive entries to open. The cells ask the model for a thumbnail as they scroll
/// into view, and the model keeps a bounded number of them.
struct ThumbnailStrip: View {
    @Environment(\.theme) private var theme

    let model: ReaderModel
    /// The page the reader is on, in the publication's own numbering.
    let currentIndex: Int
    let onSelect: (Int) -> Void

    private let cellWidth: CGFloat = 64

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: StoryArcSpace.sm) {
                    ForEach(model.pages.indices, id: \.self) { index in
                        ThumbnailCell(
                            model: model,
                            index: index,
                            isCurrent: index == currentIndex,
                            width: cellWidth,
                            onSelect: onSelect
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, StoryArcSpace.md)
                .padding(.vertical, StoryArcSpace.sm)
            }
            // Opens on the page being read rather than at page one, which is the
            // only position a reader forty pages in would have to scroll away from.
            .onAppear { scroller.scrollTo(currentIndex, anchor: .center) }
            .onChange(of: currentIndex) { _, new in
                withAnimation(.easeInOut(duration: 0.2)) { scroller.scrollTo(new, anchor: .center) }
            }
        }
        // No fixed height: a horizontal ScrollView takes its content's height, and a
        // pinned 112 pt clipped the page number away at a large text size.
        //
        // No glass either, since `comic-reader` moved the browser off the page and into the
        // menu's own surface. Glass is for a shape floating over artwork; painted onto a
        // sheet it is a second material over a first one, and the cells' own theme colours
        // are already sized for that background.
    }
}

private struct ThumbnailCell: View {
    @Environment(\.theme) private var theme

    let model: ReaderModel
    let index: Int
    let isCurrent: Bool
    let width: CGFloat
    let onSelect: (Int) -> Void

    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: StoryArcSpace.hair) {
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    // No spinner per cell: eight of them spinning while a strip
                    // scrolls is worse than eight quiet rectangles.
                    theme.palette.surfaceRaised
                }
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(.rect(cornerRadius: StoryArcRadius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                    .strokeBorder(
                        isCurrent ? theme.accent : theme.palette.borderSubtle,
                        lineWidth: isCurrent ? 2 : 1
                    )
            }

            Text(verbatim: "\(index + 1)")
                .textRole(.caption)
                .monospacedDigit()
                // The number, not only the border: `native-experience` forbids
                // colour as the only signal, and a border is only colour.
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? theme.accent : theme.palette.textTertiary)
        }
        .contentShape(.rect)
        .onTapGesture { onSelect(index) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("reader.thumbnail \(index + 1)", bundle: .module))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .task(id: index) {
            if image == nil { image = await model.thumbnail(at: index) }
        }
    }
}
