public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// The width at or above which the shelf stops being a widened phone.
///
/// An iPad Pro clears it in either orientation; the same iPad in a half-width Split
/// View slot does not, and gets the middle tier, which is the point of measuring.
private let confidentShelfWidth: CGFloat = 900

/// How much wider a cover is drawn once the reader is at an accessibility text size.
///
/// A step, not a scale, and there are exactly two of them. Cover width and text size are
/// not the same quantity: multiplying the cell by the font would trade away the artwork —
/// the one thing this app says is the interface — to make room for words. What a cramped
/// caption actually needs is *one fewer column*, and a column is a step.
///
/// 1.4 is chosen against the two widths that bracket every supported phone. It takes a
/// 402 pt iPhone from three columns to two — the caption goes from 112 pt, where `Ashfall
/// #1` hyphenates across two lines and its series line truncates to `Ashf…`, to 175 pt —
/// and it stops short of taking a 375 pt iPhone SE, the narrowest device on the iOS 26
/// floor, down to a single column. `library-browsing` still wants a grid at every text
/// size; it is the truncation that has to go, not the shelf.
private let accessibilityCoverStep: CGFloat = 1.4

/// The narrowest a cover may be drawn, given the room the shelf has and how large the
/// reader has asked for text to be.
///
/// Pure and free of the view so the column count can be asserted without a window. It had
/// to be: the truncation this answers was only ever going to be found by looking at a
/// booted simulator at the largest Dynamic Type size, because nothing here could be tested.
/// Android's `coverMinimumWidth` is the same function over the same two inputs.
///
/// `design.md` §4 — "Minimum cover width scales by size class: 104 / 132 / 158 pt" — is the
/// answer at every ordinary text size, unchanged. One pair for every window is what put
/// eight phone-sized cells in a 13-inch iPad: the same lattice widened, rather than the
/// fewer, larger, more confident covers a big window is for. The text size only decides
/// whether the tier is taken as written or one step wider.
func coverMinimumWidth(shelfWidth: CGFloat, textSize: DynamicTypeSize) -> CGFloat {
    let tier: CGFloat = switch shelfWidth {
    case ..<StoryArcWindowClass.sidebarWidthThreshold: 104
    case ..<confidentShelfWidth: 132
    default: 158
    }
    guard textSize.isAccessibilitySize else { return tier }
    return (tier * accessibilityCoverStep).rounded()
}

/// The cover grid.
///
/// `library-browsing`: "the number of grid columns follows the available width,
/// and cover size stays within the readable range defined in the design tokens".
/// `adaptive` is what does that — a fixed column count would give a phone
/// postage stamps and an iPad a wall of enormous covers.
struct CoverGrid: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale
    /// How large the reader has asked for text to be. The second input to the cover size —
    /// see ``coverMinimumWidth(shelfWidth:textSize:)``.
    @Environment(\.dynamicTypeSize) private var textSize

    let publications: [Publication]
    /// Search results under their own headings. Empty means there is no search running and
    /// the shelf is drawn as one run of covers.
    var groups: [MatchGroup] = []
    let model: LibraryModel

    // No `onOpen`. A cover leads to the publication's page now — `publication-detail` makes
    // that the rule for every cover on every surface — and ``CoverCell`` pushes the route
    // itself, so the enclosing stack's one registration is the whole wiring. The grid used
    // to carry a `Continue reading` row of its own, which was the only resume affordance
    // here; it moved to the home surface's hero long before this change and had been passed
    // an empty array by every caller since.

    /// What the reader has picked, or `nil` when they are not picking.
    ///
    /// `collections-and-reading-lists` wants publications "selected in bulk from the
    /// library", and the library is a grid or a list depending on a control the reader
    /// already owns — so both of them take this, and neither is the one that works.
    var selection: Set<String>?
    var onToggle: (Publication) -> Void = { _ in }

    /// How much room the shelf itself has.
    ///
    /// Measured rather than read from `horizontalSizeClass`, for the reason
    /// ``LibraryView`` gives for measuring the window: a size class is coarse, and it
    /// answers the wrong question here anyway. This grid is a *column* of a window — a
    /// regular-width iPad showing a sidebar hands the shelf a good 300 pt less than the
    /// same iPad without one, and a shelf pushed into a detail column is narrower still.
    /// So the input is the width of the grid, not of the device.
    @State private var width: CGFloat = 0

    /// The readable range. Below the minimum a cover stops being recognisable;
    /// above the maximum a phone shows one and a half of them.
    private var minimumWidth: CGFloat {
        coverMinimumWidth(shelfWidth: width, textSize: textSize)
    }

    /// Headroom over the minimum, so the last column grows into the leftover instead of
    /// leaving a ragged margin down the trailing edge. 1.6 is the ratio the single
    /// hard-coded pair already used, kept so a phone still shows the three columns it
    /// shows today.
    private var maximumWidth: CGFloat { (minimumWidth * 1.6).rounded() }

    var body: some View {
        ScrollView {
            // `library-browsing`: while a search is running, results are "grouped by match
            // kind". One heading and one grid per group rather than a second screen — the
            // reader is looking at their library with a word typed over it, not somewhere
            // else.
            if groups.isEmpty {
                grid(publications)
            } else {
                ForEach(groups) { group in
                    MatchHeading(kind: group.kind)
                    grid(group.publications)
                }
            }
        }
        // The one input to the cover size, and it is this grid's own width. Same
        // measurement `LibraryView` makes of the window, one level down, so a Split View
        // drag, a rotation and a sidebar appearing are all the same event: it changed.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @ViewBuilder
    private func grid(_ items: [Publication]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: minimumWidth, maximum: maximumWidth),
                    spacing: StoryArcSpace.md,
                    // Top, not the default centre. A cell is a cover with a
                    // caption under it, and a caption runs to one, two or three
                    // lines depending on the title and whether there is a
                    // series. Centring makes the row as tall as its wordiest
                    // cell and then floats every *cover* to a different height,
                    // so a shelf of artwork looks misaligned. Aligning to the
                    // top puts every cover on one line and lets the captions
                    // below it end where they end.
                    alignment: .top
                )
            ],
            spacing: StoryArcSpace.lg
        ) {
            ForEach(items) { publication in
                CoverCell(
                    publication: publication,
                    model: model,
                    // Pixels, not points: a cover decoded at point size is
                    // blurry on every device made since 2010.
                    maxPixelSize: Int(maximumWidth * displayScale),
                    isPicked: selection?.contains(publication.id),
                    onToggle: onToggle
                )
            }
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.md)
    }
}

// `ContinueReadingRow` used to be here. `library-browsing`'s "a Continue reading row appears
// first" moved to `home-screen` — the row became the home surface's hero, because the shelf
// hid it the moment a search or a selection started, which is exactly when a reader is
// looking hardest. Every caller had been passing this grid an empty array ever since, so the
// row was drawn nowhere; it goes rather than becoming the one cover on the browse path that
// still opened the reader after `publication-detail` decided covers lead to the page.

/// Whether a cover is one of the ones the reader has picked.
///
/// A mark in the corner rather than a tint over the artwork: the artwork is the interface,
/// and a wash of accent colour across a cover hides the one thing the reader is using to
/// tell it from its neighbour.
struct PickMark: View {
    @Environment(\.theme) private var theme

    let isPicked: Bool

    var body: some View {
        Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isPicked ? theme.palette.surfaceCanvas : .white,
                isPicked ? theme.accent : .black.opacity(0.35)
            )
            .font(.title3)
            .padding(StoryArcSpace.xs)
            // Announced by the cell, which already speaks the title this belongs to.
            .accessibilityHidden(true)
    }
}

/// Whether the app itself holds this publication's bytes.
///
/// `design.md` asks for "downloaded state as a small filled mark in one corner", and the
/// palette describes `status/downloaded` as "the one badge permitted to compete with cover
/// art". Neither platform drew it, so the only thing the shelf could say about a cover was
/// how far into it the reader had got. This is the other question a shelf is asked — can I
/// read this with no network — and it is the axis the library's own scope selector is
/// moving to, so it had better be visible on the covers.
///
/// Filled, and the only status colour in the grid. A glyph on its own ground reads over any
/// artwork; an unfilled one is a shape lost in whatever the cover happens to be.
///
/// It stands down while the reader is picking. `library-browsing` caps a cover at two marks
/// and forbids a third "for any reason", so ``PickMark`` takes this one's place rather than
/// joining it — see ``CoverCell/showsOnDeviceMark``.
struct OnDeviceMark: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: "arrow.down.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(theme.palette.surfaceCanvas, StoryArcColor.Status.downloaded)
            .font(.subheadline)
            .padding(StoryArcSpace.xs)
            // Announced by the cell, which already names the publication this belongs to.
            .accessibilityHidden(true)
    }
}

/// How far through a publication the reader got.
///
/// `library-browsing`: "its cover carries an unobtrusive progress indicator", and
/// "a fully read publication is distinguishable at a glance without a label
/// covering the artwork". A bar along the foot does both — it never crosses the
/// artwork, and a full one reads as finished without a word on top of the cover.
struct ProgressBar: View {
    @Environment(\.theme) private var theme

    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.black.opacity(0.35))
                Rectangle()
                    .fill(fraction >= 1 ? theme.palette.textSecondary : theme.accent)
                    .frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: StoryArcSpace.hair * 2)
        // Decorative: the cell speaks its progress in its own label, and a second
        // announcement between the title and the format would just be noise.
        .accessibilityHidden(true)
    }
}
