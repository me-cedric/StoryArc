import SwiftUI

import DesignSystem
import LibraryFeature
import StoryArcCore

/// Everything on this device, as a shelf.
///
/// The delta to `offline-downloads` asks for the on-device destination to be "presented
/// with the same grid, the same cells and the same publication pages as the library" —
/// because "a reader before a flight sees what they can read rather than what was fetched".
/// A grid of covers is what makes this a library rather than a list of transfers, and it is
/// the difference the whole destination turns on.
///
/// Its own cells rather than `LibraryFeature`'s, for the same reason `HomeShelf` has its
/// own: the library's `CoverGrid` is internal to that module and carries a selection model,
/// a match-group layout and a bulk-action path that none of them belong on this screen. The
/// two rules that matter — a 4 pt radius because a comic cover is printed stock, and
/// letterboxing onto `surfaceSunken` rather than cropping the artwork — are `design.md`'s,
/// and they are held here as they are held there.
struct OnDeviceShelf: View {
    @Environment(\.theme) private var theme
    /// How large the reader has asked for text to be — the second input to the cover width.
    /// See ``LibraryFeature/coverMinimumWidth(shelfWidth:textSize:)``.
    @Environment(\.dynamicTypeSize) private var textSize

    let publications: [Publication]
    let model: LibraryModel

    /// Whether this publication is one the app can take off the device.
    ///
    /// False for a file the reader picked themselves. A folder they chose is on this device
    /// because they put it there, and an app that offered to delete it from a downloads
    /// screen would be reaching outside what it fetched.
    let removable: (Publication) -> Bool

    let onRemove: (Publication) -> Void

    /// How much room this shelf itself has.
    ///
    /// Measured, for the reason ``LibraryFeature/CoverGrid`` measures it: a size class is
    /// coarse and answers about the device rather than about the column the shelf was given.
    @State private var width: CGFloat = 0

    /// The narrowest a cover is drawn, given the room and the reader's text size.
    ///
    /// The library's own rule, asked rather than copied. This shelf held
    /// `sizeClass == .regular ? 158 : 104` — `design.md` §4's tiers with the text size left
    /// out — which is the defect `CoverGrid` and `SectionedShelf` were both fixed for and
    /// this screen was not: at an accessibility text size the downloads destination kept
    /// three columns and its captions ran out of column, while the shelf next door had
    /// already dropped to two. That is what Apple's own audit reported here as five clipped
    /// captions and reported nowhere else.
    private var minimumWidth: CGFloat {
        coverMinimumWidth(shelfWidth: width, textSize: textSize)
    }

    /// Headroom over the minimum, so the last column grows into the leftover rather than
    /// leaving a ragged trailing margin. The library's ratio, for the same reason as above:
    /// a flat 168 pt ceiling stopped the covers growing with the step this shelf now takes.
    private var maximumWidth: CGFloat { (minimumWidth * 1.6).rounded() }

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Text("downloads.onDevice")
                .textRole(.title3)
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.horizontal, StoryArcSpace.gutter)

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: minimumWidth, maximum: maximumWidth),
                        // `md`, which is what both of the library's grids use between
                        // columns and what `CoverMinimumWidthTests` counts columns with.
                        // This shelf used `coverGap`, two points wider, so the same rule
                        // asked on the same window could still hand the two screens
                        // different columns.
                        spacing: StoryArcSpace.md,
                        alignment: .top
                    )
                ],
                alignment: .leading,
                spacing: StoryArcSpace.lg
            ) {
                ForEach(publications) { publication in
                    // The publication's page, not the reader. The delta to
                    // `offline-downloads` asks this destination for "the same grid, the same
                    // cells and the same publication pages as the library", and
                    // `publication-detail` makes that a rule rather than a resemblance: a
                    // cover here is a cover. It is also where the page earns its keep on this
                    // screen — the reader who is deciding what to take on a flight is exactly
                    // the reader who wants to know what a book is before opening it.
                    NavigationLink(value: PublicationRoute(publication)) {
                        cell(publication)
                    }
                    .buttonStyle(.plain)
                    // The removal is a long press rather than a control on every cell.
                    // The artwork is the interface: a trash glyph on each cover is chrome
                    // competing with the thing it sits on, and this screen is read far
                    // more often than it is pruned.
                    .contextMenu {
                        if removable(publication) {
                            Button(role: .destructive) {
                                onRemove(publication)
                            } label: {
                                Label {
                                    Text("downloads.remove.action \(publication.displayTitle)")
                                } icon: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, StoryArcSpace.gutter)
        }
        // The one input to the cover width that is not the reader's text size, measured
        // where the library measures it: the whole width the shelf was handed, gutters
        // included, so a rotation, a Split View drag and a sidebar appearing are all the
        // same event.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func cell(_ publication: Publication) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            OnDeviceCover(publication: publication, model: model)
            // `footnote`, which is the role the library's own cell captions a cover with.
            // This shelf used `subheadline`, two points larger in a column of the same
            // width, and that is the second half of the clipped captions: a lazy grid sizes
            // a cell against the column's *maximum* and then draws it at the column's real
            // width, so a caption that fits one line at the maximum and needs two at the
            // real width is handed one line's height and asked to draw two. The smaller
            // role is not a number lowered to silence a check — it is what makes a cover
            // here caption itself the way a cover in the library does, which is what this
            // screen's own contract asks for.
            Text(publication.displayTitle)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                // The height a caption is given follows the text it actually has to draw,
                // rather than the height the grid guessed from a wider column.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One cover, decoded when the cell appears.
///
/// The same lazy extraction the library's grid uses — `publication-formats` asks for covers
/// to be pulled "as rows approach the viewport" rather than during the scan — reached
/// through the model, which caches the decode so a cover here and the same cover on the
/// shelf are one image and not two.
private struct OnDeviceCover: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    let publication: Publication
    let model: LibraryModel

    @State private var image: CGImage?

    /// What the decode is asked for, rather than the drawn width: the cell is sized by the
    /// grid and a decode keyed on a measured width would be re-run on every reflow.
    private static let decodePixels = 512

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
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        // 4 pt, not the card radius. `design.md`: "A comic cover is printed stock.
        // Rounding it like an app icon reads as wrong."
        .clipShape(.rect(cornerRadius: StoryArcRadius.cover))
        .task(id: publication.id) {
            image = await model.cover(for: publication, maxPixelSize: Self.decodePixels)
        }
        .accessibilityHidden(true)
    }
}
