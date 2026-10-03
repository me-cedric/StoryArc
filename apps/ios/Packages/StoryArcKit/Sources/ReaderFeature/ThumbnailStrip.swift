public import SwiftUI

internal import DesignSystem

/// Every page, as a carousel that centres one.
///
/// `page-browser-carousel`: "the thumbnail browser of a publication … SHALL [be] a
/// carousel that centres one page … drawn larger than the pages beside it … and marked
/// as current" and, with chapter markers, names the centred page's chapter above itself
/// and badges each chapter's first page.
///
/// Lazy, and it has to be: a 300-page comic's strip would otherwise read 300 archive
/// entries to open. The cells ask the model for a thumbnail as they scroll into view,
/// and the model keeps a bounded number of them.
struct ThumbnailStrip: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: ReaderModel
    /// The page the reader is on, in the publication's own numbering. Marked as
    /// current; the centred page is a separate, swipeable preview — see ``centredIndex``.
    let currentIndex: Int
    /// The page the carousel previews, driven by a swipe of its own or by a drag on
    /// `ReaderSlider`. `page-browser-carousel` §2 and §3.
    @Binding var centredIndex: Int?
    let isRightToLeft: Bool
    let onSelect: (Int) -> Void

    @State private var markers: [ChapterMarker] = []

    private let cellWidth: CGFloat = 64
    // design.md §1: "about 1.6 times as wide as its neighbours".
    nonisolated static let centredCellWidth: CGFloat = 64 * 1.6
    /// The page number's own row, below the tallest (centred) cell.
    private let pageNumberRowHeight: CGFloat = 28

    private var effectiveCentredIndex: Int { centredIndex ?? currentIndex }

    private var chapterLabel: ChapterLabel? {
        ChapterBrowser.chapterLabel(at: effectiveCentredIndex, markers: markers)
    }

    var body: some View {
        VStack(spacing: StoryArcSpace.xs) {
            chapterNameHeader

            GeometryReader { geometry in
                let sideMargin = Self.contentMargin(viewportWidth: geometry.size.width)

                ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: StoryArcSpace.sm) {
                        ForEach(model.pages.indices, id: \.self) { index in
                            cell(at: index)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, StoryArcSpace.sm)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centredIndex)
                .contentMargins(.horizontal, sideMargin, for: .scrollContent)
                // Scoped to the scroll content alone, as `ReaderSlider`'s mirror is
                // scoped to the slider alone: the header text keeps its own direction.
                .environment(\.layoutDirection, sliderLayoutDirection(isRightToLeft: isRightToLeft))
                // `.scrollPosition(id:)` does not move a lazy stack that has not laid out
                // yet, so the carousel opened at page one with the current page drawn wide
                // beside it. One explicit scroll once it is on screen puts it in the middle.
                .onAppear { proxy.scrollTo(effectiveCentredIndex, anchor: .center) }
                }
            }
            .frame(height: Self.centredCellWidth * 1.5 + StoryArcSpace.sm * 2 + pageNumberRowHeight)
        }
        .task(id: model.publication.id) { markers = await model.chapterMarkers() }
        .onAppear { if centredIndex == nil { centredIndex = currentIndex } }
        // A page turned while the carousel is open (behind the half-height menu, or by a
        // VoiceOver step on the slider) moves the preview to it.
        .onChange(of: currentIndex) { _, new in centredIndex = new }
    }

    /// The margin on each side of the carousel's content.
    ///
    /// `.viewAligned` snaps a cell's leading edge to this margin, and the cell that lands
    /// there becomes the centred one, at ``centredCellWidth``. So the margin leaves room
    /// for that wide cell, not for a neighbour, or the centred page sits off the middle.
    /// The same margin is what lets the first and the last page reach the centre.
    nonisolated static func contentMargin(viewportWidth: CGFloat) -> CGFloat {
        max(0, (viewportWidth - centredCellWidth) / 2)
    }

    /// The name above the carousel, for the chapter the centred page is in.
    ///
    /// Hidden from the accessibility tree rather than merely unfocusable — SwiftUI has
    /// no middle ground between the two — because each cell's own label already names
    /// its chapter (``chapterCellLabel(at:)``). `page-browser-carousel` §6: "a live label
    /// that is not focusable, so a moving carousel is not read twice".
    @ViewBuilder
    private var chapterNameHeader: some View {
        if let chapterLabel {
            Group {
                switch chapterLabel {
                case .named(let title):
                    Text(verbatim: title)
                case .position(let position):
                    Text("reader.chapter.number \(position)", bundle: .module)
                }
            }
            .textRole(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(theme.palette.textSecondary)
            .accessibilityHidden(true)
        }
    }

    /// What a cell's accessibility label adds to "Page %d" — the chapter the page at
    /// `index` is in, read the same way the header above names it.
    private func chapterCellLabel(at index: Int) -> Text? {
        switch ChapterBrowser.chapterLabel(at: index, markers: markers) {
        case .named(let title): Text(verbatim: title)
        case .position(let position): Text("reader.chapter.number \(position)", bundle: .module)
        case nil: nil
        }
    }

    /// One cell, broken out of the `ForEach` so the compiler can type-check it: the
    /// combined cell, scale transition and conditional outline in one expression timed
    /// out rather than failing, which is its own lesson for the next cell added here.
    private func cell(at index: Int) -> some View {
        let badgeText = ChapterBrowser.badgeText(at: index, markers: markers)
        let chapterName = chapterCellLabel(at: index)
        let width = index == effectiveCentredIndex ? Self.centredCellWidth : cellWidth
        return ThumbnailCell(
            model: model,
            index: index,
            isCurrent: index == currentIndex,
            width: width,
            badgeText: badgeText,
            chapterName: chapterName,
            onSelect: onSelect
        )
        .id(index)
        .scrollTransition(.animated, axis: .horizontal) { content, phase in
            content.scaleEffect(reduceMotion ? 1 : 1 - min(abs(phase.value), 1) * 0.1)
        }
        .overlay { centredOutline(isCentred: index == effectiveCentredIndex) }
    }

    /// Reduce Motion scenario: with no scale, this outline is what marks the centred
    /// page.
    @ViewBuilder
    private func centredOutline(isCentred: Bool) -> some View {
        if reduceMotion, isCentred {
            RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                .strokeBorder(theme.accent.opacity(0.6), lineWidth: 2)
        }
    }
}

private struct ThumbnailCell: View {
    @Environment(\.theme) private var theme

    let model: ReaderModel
    let index: Int
    let isCurrent: Bool
    let width: CGFloat
    let badgeText: String?
    let chapterName: Text?
    let onSelect: (Int) -> Void

    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: StoryArcSpace.hair) {
            ZStack(alignment: .topLeading) {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    // No spinner per cell: eight of them spinning while a strip
                    // scrolls is worse than eight quiet rectangles.
                    theme.palette.surfaceRaised
                }

                if let badgeText {
                    Text(verbatim: badgeText)
                        .textRole(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, StoryArcSpace.xs)
                        .padding(.vertical, StoryArcSpace.hair)
                        .background(.thinMaterial, in: Capsule())
                        .padding(StoryArcSpace.hair)
                        .accessibilityHidden(true)
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
            // Centred in a box as tall as the centred page, so every page number sits on
            // one line under the carousel, as the neighbours sit centred beside it.
            .frame(height: ThumbnailStrip.centredCellWidth * 1.5)

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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .task(id: index) {
            if image == nil { image = await model.thumbnail(at: index) }
        }
    }

    /// "Page %d", plus the chapter name when there is one. `page-browser-carousel` §6.
    private var accessibilityLabel: Text {
        let page = Text("reader.thumbnail \(index + 1)", bundle: .module)
        guard let chapterName else { return page }
        return Text("\(page), \(chapterName)")
    }
}
