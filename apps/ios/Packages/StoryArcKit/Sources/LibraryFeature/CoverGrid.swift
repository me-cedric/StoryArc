public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// The cover grid.
///
/// `library-browsing`: "the number of grid columns follows the available width,
/// and cover size stays within the readable range defined in the design tokens".
/// `adaptive` is what does that — a fixed column count would give a phone
/// postage stamps and an iPad a wall of enormous covers.
struct CoverGrid: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    let publications: [Publication]
    /// In-progress publications, most recently read first. Empty means the row is
    /// not drawn — `library-browsing` requires it absent rather than shown empty.
    var continueReading: [Publication] = []
    /// Search results under their own headings. Empty means there is no search running and
    /// the shelf is drawn as one run of covers.
    var groups: [MatchGroup] = []
    let model: LibraryModel
    /// What to do when a cover is tapped. The library does not open the reader
    /// itself — a feature module never depends on another feature module, so the
    /// app layer wires the two together.
    let onOpen: (Publication) -> Void

    /// What the reader has picked, or `nil` when they are not picking.
    ///
    /// `collections-and-reading-lists` wants publications "selected in bulk from the
    /// library", and the library is a grid or a list depending on a control the reader
    /// already owns — so both of them take this, and neither is the one that works.
    var selection: Set<String>?
    var onToggle: (Publication) -> Void = { _ in }

    /// The readable range. Below the minimum a cover stops being recognisable;
    /// above the maximum a phone shows one and a half of them.
    private let minimumWidth: CGFloat = 108
    private let maximumWidth: CGFloat = 168

    var body: some View {
        ScrollView {
            if !continueReading.isEmpty {
                ContinueReadingRow(
                    publications: continueReading,
                    model: model,
                    onOpen: onOpen,
                    maxPixelSize: Int(maximumWidth * displayScale)
                )
            }

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
                    onOpen: onOpen,
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

/// What the reader was in the middle of.
///
/// `library-browsing`: "a Continue reading row appears first, ordered by most
/// recently read". Horizontal, because it is a shortcut rather than a second
/// library — a vertical block of it would push the shelf off the screen.
struct ContinueReadingRow: View {
    @Environment(\.theme) private var theme

    let publications: [Publication]
    let model: LibraryModel
    let onOpen: (Publication) -> Void
    let maxPixelSize: Int

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("library.continueReading", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.horizontal, StoryArcSpace.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: StoryArcSpace.md) {
                    ForEach(publications) { publication in
                        CoverCell(
                            publication: publication,
                            model: model,
                            onOpen: onOpen,
                            maxPixelSize: maxPixelSize
                        )
                        .frame(width: 128)
                    }
                }
                .padding(.horizontal, StoryArcSpace.gutter)
            }
        }
        .padding(.top, StoryArcSpace.md)
        .padding(.bottom, StoryArcSpace.sm)
    }
}

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
