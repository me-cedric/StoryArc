internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// One cover, decoded when it comes into view, drawn at the size Home gives it.
///
/// Home's whole argument is that a comic cover is the most beautiful thing this app has,
/// so it is shown at size rather than as a thumbnail. That leaves one real problem: a
/// hero frame is not 2:3, and neither is half a library — a manga volume and a square
/// ebook cover are their own proportions and `design.md` forbids distorting either.
///
/// So the art is always **fitted**, never stretched, and the space a fitted cover does not
/// fill is filled by the cover itself, blurred out of focus. That is the same
/// cover-derived wash `design.md` already asks for behind a publication's detail screen,
/// and it is derived from the artwork rather than painted over it: the app is still not
/// tinting anybody's cover.
///
/// The decode goes through the model, which caches it, so a cover on Home and the same
/// cover on the shelf are one image and not two.
struct HomeArtwork: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    let publication: Publication
    let model: LibraryModel

    /// The widest this will be drawn, which is the resolution it is decoded at.
    let width: CGFloat

    /// Whether the frame is filled with a blurred copy of the art behind the fitted one.
    ///
    /// True for the hero, where the frame is wider than any cover and a bare well would
    /// read as a rendering fault. False for a shelf cover, which is already 2:3 and has
    /// nothing to fill.
    var washesBehind = false

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            theme.palette.surfaceSunken

            if let image {
                if washesBehind {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 44, opaque: true)
                        .opacity(0.75)
                }
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .clipped()
        .task(id: publication.id) {
            image = await model.cover(for: publication, maxPixelSize: Int(width * displayScale))
        }
        .accessibilityHidden(true)
    }

    /// The shared well rather than an empty rectangle.
    ///
    /// The same view the grid, the publication page and the player draw — see
    /// ``CoverlessWell``. This one used to pass `format: nil`, on the reasoning that naming
    /// the format crowds a shelf card, while the grid's cell of the same size named it: two
    /// surfaces disagreeing about one treatment, which is the whole of what the September
    /// sweep found and what moving the view to `DesignSystem` is meant to end.
    @ViewBuilder
    private var placeholder: some View {
        CoverlessWell(format: publication.format)
    }
}
