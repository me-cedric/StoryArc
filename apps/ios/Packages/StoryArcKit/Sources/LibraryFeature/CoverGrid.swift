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
    let model: LibraryModel
    /// What to do when a cover is tapped. The library does not open the reader
    /// itself — a feature module never depends on another feature module, so the
    /// app layer wires the two together.
    let onOpen: (Publication) -> Void

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
                ForEach(publications) { publication in
                    CoverCell(
                        publication: publication,
                        model: model,
                        onOpen: onOpen,
                        // Pixels, not points: a cover decoded at point size is
                        // blurry on every device made since 2010.
                        maxPixelSize: Int(maximumWidth * displayScale)
                    )
                }
            }
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.vertical, StoryArcSpace.md)
        }
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

/// One publication in the grid.
struct CoverCell: View {
    @Environment(\.theme) private var theme

    let publication: Publication
    let model: LibraryModel
    let onOpen: (Publication) -> Void
    let maxPixelSize: Int

    @State private var cover: CGImage?
    @State private var didAttemptLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            artwork
                // 2:3 is the comic and book proportion. Fixing it here means a
                // cell reserves its space before its cover arrives, so the grid
                // does not reflow as images land.
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: StoryArcRadius.md))
                .overlay {
                    // A hairline rather than a shadow: a pale cover on a pale
                    // surface needs an edge, and a shadow under every cell reads
                    // as noise at grid density.
                    RoundedRectangle(cornerRadius: StoryArcRadius.md)
                        .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    if let fraction = model.readFraction(of: publication) {
                        ProgressBar(fraction: fraction)
                    }
                }

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(publication.displayTitle)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let subtitle {
                    Text(subtitle)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        // One label for the whole cell. Read as three separate elements it would
        // announce the title, then the format, then an unlabelled image.
        .contentShape(.rect)
        // A publication that cannot be read is not tappable. Opening it only to
        // show the same refusal a second time wastes the user's tap.
        .onTapGesture { if publication.isOpenable { onOpen(publication) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(publication.isOpenable ? .isButton : [])
        .task(id: publication.id) {
            guard !didAttemptLoad else { return }
            didAttemptLoad = true
            cover = await model.cover(for: publication, maxPixelSize: maxPixelSize)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover {
            Image(decorative: cover, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            // A set title rather than an empty rectangle. A grid of publications with no
            // cover art — and plenty of EPUBs carry none — was a wall of identical grey
            // cards labelled with a format, which is the one thing every card in that wall
            // had in common. The title is what tells them apart. The format stays, smaller,
            // because it is still the answer to "why is there no picture".
            ZStack(alignment: .bottom) {
                theme.palette.surfaceRaised

                Text(publication.displayTitle)
                    .textRole(.headline)
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, StoryArcSpace.sm)
                    .frame(maxHeight: .infinity)

                Text(publication.format.displayName)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
                    .padding(.bottom, StoryArcSpace.xs)
            }
        }
    }

    /// The second line: what distinguishes this row from its neighbours.
    private var subtitle: String? {
        if !publication.isOpenable {
            // Said plainly rather than shown as a broken cover. `publication-formats`
            // requires a named refusal, and a grid cell is where a user meets it.
            return String(localized: "library.cell.cannotOpen", bundle: .module)
        }
        if let series = publication.series, series != publication.displayTitle {
            return publication.number.map { "\(series) #\($0)" } ?? series
        }
        return publication.authors.first
    }

    private var accessibilityLabel: String {
        var parts = [publication.displayTitle]
        if let subtitle { parts.append(subtitle) }
        parts.append(publication.format.displayName)
        // Progress is spoken, because a bar at the foot of a cover is invisible to
        // anyone using VoiceOver and "how far in am I" is the whole point of it.
        if let fraction = model.readFraction(of: publication) {
            parts.append(
                String(
                    localized: "library.cell.progress \(Int(fraction * 100))",
                    bundle: .module
                )
            )
        }
        if let pageCount = publication.pageCount {
            parts.append(String(localized: "library.cell.pages \(pageCount)", bundle: .module))
        }
        return parts.joined(separator: ", ")
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
