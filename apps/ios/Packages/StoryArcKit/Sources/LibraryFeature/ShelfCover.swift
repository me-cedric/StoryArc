// Internal throughout: nothing here appears in this module's public surface, and an
// unused `public import` is a warning under `InternalImportsByDefault`.
internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// A shelf's own cover, drawn out of what it holds.
///
/// `collections-and-reading-lists`: a collection's cover "is a composite of its first four
/// member covers unless the user sets a specific one". ``CompositeCover`` decides which
/// four and in what order — the same decision Android's `ShelfCover` asks for — and this
/// only draws them. ``ShelfCover/tiles(of:)`` extends the same rule to a reading list,
/// where *first* means first in the reader's order rather than first by identity.
///
/// The artwork is the interface, so a shelf is a cover rather than a name with a folder
/// glyph beside it. It fills whatever it is given and keeps a cover's 2:3, so the caller
/// decides how big a shelf is and this decides only what goes on it.
struct ShelfCover: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    let model: LibraryModel
    /// The member identities to draw, in the order they are drawn.
    let tiles: [String]
    /// The widest this will ever be drawn, in points. It sizes the decode and nothing
    /// else — the frame comes from the caller, and asking for pixels the screen will never
    /// show is how ten shelves become ten full-size archive reads.
    var width: CGFloat = 180

    /// Artwork that has arrived, keyed by the member it belongs to.
    @State private var covers: [String: CGImage] = [:]

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
                // first collection is empty still lines up with the ones beside it.
                theme.palette.surfaceRaised
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        // The caption beside it says the shelf's name and how much is in it. Spoken here
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
    /// and remembers what it decoded. Ten shelves ask for forty covers, and forty archives
    /// opened on the main thread is a screen that does not move.
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

/// A shelf as the reader meets it on the Shelves screen: its artwork, then its name.
///
/// §3.6 of the revamp: "a collection with no artwork is a folder listing". So a shelf is
/// drawn the way a publication is drawn — cover first, caption under it, never over it —
/// and the two read as the same kind of thing, which is the point: a shelf is something you
/// open, not a row you tick.
struct ShelfCard: View {
    @Environment(\.theme) private var theme

    let model: LibraryModel
    let title: String
    /// Where it came from and how much is in it, already joined.
    let subtitle: String
    /// The member identities behind the composite. Empty draws the blank shelf.
    let tiles: [String]
    /// How far through an ordered shelf the reader is. Nil for a collection, which has no
    /// order and therefore no position in one.
    var progress: ShelfProgress?
    /// How many edits this shelf still owes its online library.
    var pending: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            ShelfCover(model: model, tiles: tiles)
                .clipShape(.rect(cornerRadius: StoryArcRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                        .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
                }
                // `design.md` on a cover cell: "progress as a thin rail across the bottom
                // edge, never a ring over the art". A reading list has one for the same
                // reason a publication does — it is a thing you are partway through.
                .overlay(alignment: .bottom) {
                    if let progress, progress.fraction > 0 {
                        ProgressBar(fraction: progress.fraction)
                            .clipShape(.rect(cornerRadius: StoryArcRadius.sm))
                    }
                }

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(title)
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
                    .lineLimit(1)

                // `collections-and-reading-lists`: "the pending state is visible on the
                // list". On the shelf as well as inside it, because a reader looking for
                // what has not gone out yet should not have to open every list to find it.
                if pending > 0 {
                    Text("shelves.pending \(pending)", bundle: .module)
                        .textRole(.caption)
                        .foregroundStyle(StoryArcColor.Status.offline)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }
}

/// How far through an ordered shelf the reader is.
///
/// Counted the way ``ReadingList/position(finished:)`` counts it — everything before the
/// first unfinished entry — so the rail on the card and the line inside the list can never
/// disagree about where the reader is.
struct ShelfProgress: Equatable {
    let done: Int
    let total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }
}

extension ShelfCover {
    /// The four covers a reading list stands behind, in the reader's own order.
    ///
    /// ``CompositeCover`` orders a collection's tiles by identity because a collection is a
    /// set and a set has no first. A reading list is the opposite case — its order *is* its
    /// meaning — so its first four entries are its first four tiles, and a list the reader
    /// reorders redraws itself. Everything else is ``CompositeCover``'s rule kept word for
    /// word: four tiles or one, never a quadrant with a hole in it.
    static func tiles(of list: ReadingList) -> [String] {
        guard list.entries.count >= CompositeCover.tileCount else {
            return Array(list.entries.prefix(1))
        }
        return Array(list.entries.prefix(CompositeCover.tileCount))
    }
}
