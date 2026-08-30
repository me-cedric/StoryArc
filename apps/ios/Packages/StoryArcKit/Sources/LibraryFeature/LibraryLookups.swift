public import CoreGraphics
public import Foundation

public import Formats
internal import Persistence
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

    /// Whether the app itself holds this publication's bytes.
    ///
    /// `offline-downloads` promises that what has been downloaded stays readable, and
    /// `design.md` asks the grid to say so with "a small filled mark in one corner".
    /// This is the question behind that mark, and the answer has to be cheap: it is
    /// asked once per visible cell on every redraw, so it is a path comparison against
    /// a location the model already holds and never a read of the download store.
    /// ``keptOffline`` is the store-reading answer, deliberately kept for the two places
    /// that ask it when the reader acts rather than when the shelf draws.
    ///
    /// A publication found by a folder scan is on the device too, but not *kept* by the
    /// app: the folder can be unmounted, the card pulled, the bookmark staled — which is
    /// what ``LibraryModel/unavailableFolders`` exists for. Only a copy in the app's own
    /// storage carries the promise, so only that copy earns the mark.
    func isOnDevice(_ publication: Publication) -> Bool {
        guard let store = downloadStore, let url = locations[publication.id] else { return false }
        // Trailing separator on the folder, so a sibling directory whose name merely
        // begins with the store's — `…/Downloads-old` beside `…/Downloads` — is not
        // read as being inside it.
        let folder = store.directory.standardizedFileURL.path(percentEncoded: false)
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return url.standardizedFileURL.path(percentEncoded: false).hasPrefix(prefix)
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
