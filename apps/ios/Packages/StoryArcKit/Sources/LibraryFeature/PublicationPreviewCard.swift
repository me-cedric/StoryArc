internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// What a long press shows before ``PublicationActionMenu`` opens.
///
/// `library-browsing`'s *A publication's actions wherever it is drawn* asks for iOS's own
/// gesture, "a context menu" — and the system draws no preview unless one is given. Decoded
/// for itself rather than handed whatever cover state the page around it already holds: the
/// pages this reaches decode a cover several different ways — ``CoverCell`` keeps one in a
/// `@State`, ``HomeArtwork`` keeps its own, a catalogue row has none at all until the menu
/// asks — and a preview that depended on each one's own cache would be a rule repeated at
/// every call site rather than asked once. The decode runs only when a reader actually
/// presses and holds, which is when SwiftUI evaluates this closure.
struct PublicationPreviewCard: View {
    @Environment(\.theme) private var theme

    let publication: Publication
    let model: LibraryModel

    @State private var cover: CGImage?

    /// Wide enough to read as the cover a reader is about to act on, narrow enough that the
    /// system's own preview chrome around it does not dwarf the screen beneath it.
    private static let width: CGFloat = 220

    /// What the preview decodes at — sized for this card's own width rather than the
    /// decode a shelf cell already asked for at its own, smaller one.
    private static let decodePixels = 440

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            artwork
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .frame(width: Self.width)
                .clipShape(.rect(cornerRadius: StoryArcRadius.cover))

            Text(publication.displayTitle)
                .textRole(.subheadline)
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)
                .frame(width: Self.width, alignment: .leading)
        }
        .padding(StoryArcSpace.md)
        .task(id: publication.id) {
            cover = await model.cover(for: publication, maxPixelSize: Self.decodePixels)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover {
            ZStack {
                theme.palette.surfaceSunken
                Image(decorative: cover, scale: 1)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            // A browsed Kavita chapter or OPDS row this device has never fetched has
            // nothing `model.cover(for:maxPixelSize:)` can decode — the same well the
            // library draws for any publication with no artwork, per `design.md`.
            CoverlessWell(format: publication.format)
        }
    }
}
