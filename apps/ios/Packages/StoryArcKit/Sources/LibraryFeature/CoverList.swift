public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// The compact list.
///
/// `library-browsing` requires a list beside the grid: past a certain size a
/// library is scanned by title rather than recognised by artwork, and a screen of
/// covers holds nine rows where a list holds twenty.
///
/// The same cells' worth of information, laid out for reading rather than for
/// looking: a small cover, the title, what distinguishes it, and how far in the
/// reader got.
struct CoverList: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    let publications: [Publication]
    let model: LibraryModel
    let onOpen: (Publication) -> Void

    /// What the reader has picked, or `nil` when they are not picking.
    ///
    /// `collections-and-reading-lists` asks for bulk selection from the library, and the
    /// library is whichever of these two layouts the reader chose. Selecting in one and not
    /// the other would make the layout toggle a feature switch.
    var selection: Set<String>?
    var onToggle: (Publication) -> Void = { _ in }

    private let thumbnailWidth: CGFloat = 44

    var body: some View {
        List(publications) { publication in
            ListRow(
                publication: publication,
                model: model,
                onOpen: onOpen,
                thumbnailWidth: thumbnailWidth,
                maxPixelSize: Int(thumbnailWidth * displayScale),
                isPicked: selection?.contains(publication.id),
                onToggle: onToggle
            )
            .listRowBackground(theme.palette.surfaceCanvas)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

struct ListRow: View {
    @Environment(\.theme) private var theme

    let publication: Publication
    let model: LibraryModel
    let onOpen: (Publication) -> Void
    let thumbnailWidth: CGFloat
    let maxPixelSize: Int

    /// Whether this one is picked, or `nil` when the library is not in selection mode.
    var isPicked: Bool?
    var onToggle: (Publication) -> Void = { _ in }

    @State private var cover: CGImage?

    /// The server whose list just refused this publication, if one did.
    @State private var refusedServer: String?

    var body: some View {
        HStack(spacing: StoryArcSpace.md) {
            if let isPicked { PickMark(isPicked: isPicked) }

            thumbnail
                .frame(width: thumbnailWidth, height: thumbnailWidth * 1.5)
                .clipShape(.rect(cornerRadius: StoryArcRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                        .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(publication.displayTitle)
                    .textRole(.body)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let fraction = model.readFraction(of: publication) {
                // A number here rather than a bar: a list row is read, and "48%"
                // is quicker to read than a sliver of colour is to measure.
                Text("library.cell.progress \(Int(fraction * 100))", bundle: .module)
                    .textRole(.caption)
                    .monospacedDigit()
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .contentShape(.rect)
        // While the reader is picking, a tap picks. Opening the reader mid-selection would
        // throw away everything they had chosen so far.
        .onTapGesture {
            if isPicked != nil {
                onToggle(publication)
            } else if publication.isOpenable {
                onOpen(publication)
            }
        }
        // The same long press the grid answers. `native-experience` asks for the system's
        // context menu wherever the app needs one, and a publication does not stop having
        // shelves because the reader switched to the list layout — until this was here,
        // marking something read was a thing you could only do in the grid, which is a rule
        // no reader could have guessed.
        //
        // Absent while picking, for the reason the grid's is: the bar below is already
        // offering the same actions for everything that is picked.
        .contextMenu {
            if isPicked == nil {
                AddToShelfMenu(model: model, publications: [publication]) { refusedServer = $0 }
            }
        }
        .refusedByServer($refusedServer, model: model, publication: publication)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(publication.isOpenable ? .isButton : [])
        .accessibilityAddTraits(isPicked == true ? .isSelected : [])
        .task(id: publication.id) {
            if cover == nil {
                cover = await model.cover(for: publication, maxPixelSize: maxPixelSize)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let cover {
            Image(decorative: cover, scale: 1).resizable().scaledToFill()
        } else {
            theme.palette.surfaceRaised
        }
    }

    /// What distinguishes this row from its neighbours, format included: in a list
    /// the artwork is too small to say what kind of publication this is.
    private var subtitle: String {
        var parts: [String] = []
        if !publication.isOpenable {
            parts.append(String(localized: "library.cell.cannotOpen", bundle: .module, locale: .storyArc))
        }
        if let series = publication.series, series != publication.displayTitle {
            parts.append(publication.number.map { "\(series) #\($0)" } ?? series)
        } else if let author = publication.authors.first {
            parts.append(author)
        }
        parts.append(publication.format.displayName)
        return parts.joined(separator: " · ")
    }
}
