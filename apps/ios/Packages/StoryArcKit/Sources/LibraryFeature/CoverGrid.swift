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
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: minimumWidth, maximum: maximumWidth),
                        spacing: StoryArcSpace.md
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
            // A placeholder that names the format rather than an empty rectangle:
            // while a cover is loading, the format is the most useful thing the
            // cell knows, and it is also the honest answer for a publication that
            // has no cover at all.
            ZStack {
                theme.palette.surfaceRaised
                Text(publication.format.displayName)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
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
        if let pageCount = publication.pageCount {
            parts.append(String(localized: "library.cell.pages \(pageCount)", bundle: .module))
        }
        return parts.joined(separator: ", ")
    }
}
