// Internal throughout: nothing here appears in this module's public surface, and an
// unused `public import` is a warning under `InternalImportsByDefault`.
internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// A collection's own cover, drawn out of what it holds.
///
/// `collections-and-reading-lists`: a collection's cover "is a composite of its first four
/// member covers unless the user sets a specific one". ``CompositeCover`` decides which
/// four and in what order — the same decision Android's `ShelfCover` asks for — and this
/// only draws them.
///
/// The artwork is the interface, so a shelf of collections is a shelf of covers rather than
/// a list of names with a folder glyph beside each one.
struct ShelfCover: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    let model: LibraryModel
    let collection: PublicationCollection
    /// The width of the whole composite. Its height follows the 2:3 a cover has.
    var width: CGFloat = 44

    /// Artwork that has arrived, keyed by the member it belongs to.
    @State private var covers: [String: CGImage] = [:]

    private var tiles: [String] { CompositeCover.tiles(of: collection) }

    var body: some View {
        Group {
            if tiles.count >= CompositeCover.tileCount {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tile(tiles[0])
                        tile(tiles[1])
                    }
                    HStack(spacing: 0) {
                        tile(tiles[2])
                        tile(tiles[3])
                    }
                }
            } else if let only = tiles.first {
                tile(only)
            } else {
                // Nothing in it yet. A blank in the shape of a cover, so a shelf whose
                // first collection is empty still lines up with the ones below it.
                theme.palette.surfaceRaised
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(.rect(cornerRadius: StoryArcRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
        }
        // The row beside it says the collection's name and how much is in it. Spoken here
        // as well, the composite would announce four covers nobody asked to hear about.
        .accessibilityHidden(true)
        // Re-asked when the library grows, not only when the tiles change: a shelf opened
        // while the scan is still running has tiles whose publications are not there yet,
        // and a task keyed on the tiles alone would never look a second time.
        .task(id: loadKey) { await load() }
    }

    private var loadKey: [String] { tiles + ["\(model.publications.count)"] }

    @ViewBuilder
    private func tile(_ id: String) -> some View {
        Group {
            if let image = covers[id] {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                theme.palette.surfaceRaised
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// Asks the library for each tile's artwork.
    ///
    /// Through ``LibraryModel/cover(for:maxPixelSize:)``, which decodes off the main actor
    /// and remembers what it decoded. Ten collections on a shelf ask for forty covers, and
    /// forty archives opened on the main thread is a screen that does not move.
    private func load() async {
        let side = Int(width * displayScale)
        for id in tiles where covers[id] == nil {
            guard let publication = model.publications.first(where: { $0.id == id }) else {
                continue
            }
            covers[id] = await model.cover(for: publication, maxPixelSize: side)
        }
    }
}
