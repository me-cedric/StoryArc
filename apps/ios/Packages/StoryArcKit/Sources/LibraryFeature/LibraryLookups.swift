public import CoreGraphics
public import Foundation

public import Formats
public import StoryArcCore

// What a cell needs to know about one publication.
//
// Split out of `LibraryModel.swift`, which had reached the 400-line cap this project
// enforces. The division: that file is the library as a whole, this is what it can say
// about any single thing in it.

extension LibraryModel {

    /// What a publication's source is called, or `nil` when saying so would add nothing.
    ///
    /// `library-browsing`: a publication "shows its source only when more than one source
    /// is configured", and a scoped view has already answered the question in its own
    /// selector — repeating it on every row would be a column of the same word.
    public func sourceName(of publication: Publication) -> String? {
        guard registry.attributesPublications, query.scope == .allSources else { return nil }
        return registry.name(of: publication.sourceID)
    }

    /// Where a publication's file is, so the app layer can hand it to a reader.
    public func location(of publication: Publication) -> URL? {
        locations[publication.id]
    }

    // MARK: - Covers

    /// The cover for a publication, decoded once and remembered.
    ///
    /// Called by a cell as it appears, which is what makes extraction lazy. A
    /// publication with no cover returns `nil` rather than throwing: a missing
    /// cover is a normal state and the cell draws a placeholder.
    public func cover(for publication: Publication, maxPixelSize: Int) async -> CGImage? {
        if let cached = covers[publication.id] { return cached }

        // Disk before the archive. `sources` asks for a cover to be "stored on disk at
        // display resolution", and the reason is what this skips: without it every launch
        // reopened a ZIP, read its central directory, inflated an entry and decoded an
        // image, per cover, to draw a grid the reader had already seen.
        let cache = CoverCache()
        let identity = publication.id
        if let stored = await Task.detached(priority: .utility, operation: {
            cache.image(for: identity, maxPixelSize: maxPixelSize)
        }).value {
            covers[publication.id] = stored
            return stored
        }

        guard let url = locations[publication.id] else { return nil }

        let image = await Task.detached(priority: .utility) {
            let decoded = try? await CoverLoader.anyCover(
                for: publication, at: url, maxPixelSize: maxPixelSize
            )
            if let decoded { cache.store(decoded, for: identity, maxPixelSize: maxPixelSize) }
            return decoded
        }.value

        guard let image else { return nil }
        covers[publication.id] = image
        return image
    }
}
