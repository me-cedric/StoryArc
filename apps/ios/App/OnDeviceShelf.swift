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
    @Environment(\.horizontalSizeClass) private var sizeClass

    let publications: [Publication]
    let model: LibraryModel
    let onOpen: (Publication) -> Void

    /// Whether this publication is one the app can take off the device.
    ///
    /// False for a file the reader picked themselves. A folder they chose is on this device
    /// because they put it there, and an app that offered to delete it from a downloads
    /// screen would be reaching outside what it fetched.
    let removable: (Publication) -> Bool

    let onRemove: (Publication) -> Void

    /// The narrowest a cover is drawn, by size class.
    ///
    /// `design.md`: "Minimum cover width scales by size class: 104 / 132 / 158 pt". One
    /// number for every window is what leaves a tablet showing a wall of phone-sized
    /// postage stamps — a shelf reads as a shelf at a size the room can afford.
    private var minimumWidth: CGFloat { sizeClass == .regular ? 158 : 104 }

    /// The widest, so a wide window grows its covers only so far before it grows a column.
    private static let maximumWidth: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Text("downloads.onDevice")
                .textRole(.title3)
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.horizontal, StoryArcSpace.gutter)

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: minimumWidth, maximum: Self.maximumWidth),
                        spacing: StoryArcSpace.coverGap,
                        alignment: .top
                    )
                ],
                alignment: .leading,
                spacing: StoryArcSpace.lg
            ) {
                ForEach(publications) { publication in
                    Button {
                        onOpen(publication)
                    } label: {
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
    }

    private func cell(_ publication: Publication) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            OnDeviceCover(publication: publication, model: model)
            Text(publication.displayTitle)
                .textRole(.subheadline)
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
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
