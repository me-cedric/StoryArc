import SwiftUI

import DesignSystem
import LibraryFeature
import StoryArcCore

/// One horizontal run of covers on Home, under a heading.
///
/// A shelf rather than a grid: Home is the editorial surface and is never exhaustive, so a
/// section that ran out of screen would be claiming to be the library. The cells are
/// deliberately plain — the cover, letterboxed onto `surfaceSunken` at the 4 pt radius
/// `design.md` reserves for printed stock, and the title under it — because the cover is
/// the interface and a Home card that grew badges would be competing with it.
struct HomeShelf: View {
    @Environment(\.theme) private var theme

    let title: Text
    let publications: [Publication]
    let model: LibraryModel
    let onOpen: (Publication) -> Void

    /// Wide enough to be a hero on a phone and to fit three across an iPad, and the size
    /// the cover is decoded at.
    private static let coverWidth: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            title
                .textRole(.title3)
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.horizontal, StoryArcSpace.gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: StoryArcSpace.coverGap) {
                    ForEach(publications) { publication in
                        Button {
                            onOpen(publication)
                        } label: {
                            card(publication)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, StoryArcSpace.gutter)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            // Cards come to rest on their own edges rather than mid-cover, which is what
            // makes a run of art read as a shelf instead of a filmstrip that stopped
            // wherever the finger left it.
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func card(_ publication: Publication) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            HomeCover(publication: publication, model: model, width: Self.coverWidth)
            Text(publication.displayTitle)
                .textRole(.subheadline)
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: Self.coverWidth, alignment: .leading)
        }
    }
}

/// One cover, decoded when the card appears.
///
/// The same lazy extraction the grid uses — `publication-formats` asks for covers to be
/// pulled "as rows approach the viewport" rather than during the scan — reached through
/// the model, which caches the decode so a cover on Home and the same cover on the shelf
/// are one image and not two.
private struct HomeCover: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    let publication: Publication
    let model: LibraryModel
    let width: CGFloat

    @State private var image: CGImage?

    private var height: CGFloat { width * 3 / 2 }

    var body: some View {
        ZStack {
            // Letterboxed onto the sunken surface rather than filled, per `design.md`: a
            // manga volume and a square ebook cover are not 2:3, and cropping the art to
            // make them so cuts the title off the top of the artwork.
            theme.palette.surfaceSunken
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: StoryArcRadius.cover))
        .task(id: publication.id) {
            image = await model.cover(
                for: publication,
                maxPixelSize: Int(width * displayScale)
            )
        }
        .accessibilityHidden(true)
    }
}
