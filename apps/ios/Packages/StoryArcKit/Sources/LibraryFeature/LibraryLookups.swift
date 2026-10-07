public import CoreGraphics
public import Foundation

internal import Catalogue
public import Formats
internal import Kavita
internal import Persistence
public import StoryArcCore

internal import ImageIO

/// Thrown, and only ever discarded by `try?`, when a catalogue no longer lists the entry a
/// row was filed under or names no artwork for it. 11.7.
private struct OpdsArtworkNotFound: Error {}

// What a cell needs to know about one publication.
//
// Split out of `LibraryModel.swift`, which had reached the 400-line cap this project
// enforces. The division: that file is the library as a whole, this is what it can say
// about any single thing in it.

extension LibraryModel {

    // `sourceName(of:)` used to be here, and there is deliberately nothing in its place.
    // `library-browsing` requires that "nothing on the shelf states which source a
    // publication came from", so the grid stopped asking, then the list did, then the
    // spoken labels did — and the method was left behind with a doc comment describing
    // "the callers that remain", of which there were none. Origin has exactly one home
    // now, the provenance line on the publication's own page, and that line reads the
    // registry itself. A public lookup that answers a question no surface is allowed to
    // ask is an invitation to put the leak back.

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

    /// A cover already decoded for this publication, with no attempt to decode one.
    ///
    /// Task 16.10: the lock screen's artwork is asked for from a synchronous closure
    /// (``PlayerCentre/onArtwork``) that an `async` fetch cannot reach into, so this is the
    /// half of ``cover(for:maxPixelSize:)`` that closure can call — the common case, where
    /// a reader opened the book from a shelf that already drew its cover. `nil` for a book
    /// the system's own "Up Next" carousel resumed after the process died, which is Android's
    /// own caveat too (`PlayerArtwork.kt`'s `publication` parameter).
    public func cachedCover(for publication: Publication) -> CGImage? {
        covers[publication.id]
    }

    /// The cover for a publication, decoded once and remembered.
    ///
    /// Called by a cell as it appears, which is what makes extraction lazy. A
    /// publication with no cover returns `nil` rather than throwing: a missing
    /// cover is a normal state and the cell draws a placeholder.
    ///
    /// D28: this appearance is also when a share row is catalogued from its own headers,
    /// because a row built from a file name alone does not yet know where its cover is —
    /// see ``catalogueIfOnShare(_:)``.
    public func cover(for publication: Publication, maxPixelSize: Int) async -> CGImage? {
        if let cached = covers[publication.id] { return cached }

        // The reader's own picture, before anything else is read or fetched. Ahead of the
        // disk cache because the cache is keyed by `publication.id` and size alone: a cover
        // chosen after one was drawn would otherwise be answered with the one it replaced
        // until something emptied the cache. Ahead of the server rungs below because a
        // Kavita or OPDS row has no file on this device and would never reach the ladder.
        if let chosen = await CoverLadder().chosenCover(
            for: publication, maxPixelSize: maxPixelSize
        ) {
            covers[publication.id] = chosen
            return chosen
        }

        let publication = await catalogueIfOnShare(publication)

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

        guard let url = locations[publication.id] else {
            // 11.7 / D29: an OPDS row has no local file to decode a cover out of at all —
            // its artwork is fetched from the catalogue instead. 17.4: a Kavita chapter row
            // has no file either, for the same reason, and its artwork comes from the
            // server's own chapter-cover route instead.
            if let image = await opdsCover(for: publication, maxPixelSize: maxPixelSize) {
                covers[publication.id] = image
                return image
            }
            guard let image = await kavitaCover(for: publication, maxPixelSize: maxPixelSize) else {
                return nil
            }
            covers[publication.id] = image
            return image
        }

        // Task 1.3: the ladder, not `CoverLoader` directly. It is what puts the reader's
        // own picture above the bytes and a loose image beside the file below them, and it
        // is here rather than in each caller so the player and the media session get the
        // same answer this shelf does.
        let ladder = CoverLadder()
        let rung = CoverLookupRung.live
        let image = await Task.detached(priority: .utility) {
            let decoded = await rung.cover(
                for: publication, at: url, maxPixelSize: maxPixelSize, ladder: ladder
            )
            if let decoded { cache.store(decoded, for: identity, maxPixelSize: maxPixelSize) }
            return decoded
        }.value

        guard let image else { return nil }
        covers[publication.id] = image
        return image
    }

    /// An OPDS row's artwork, fetched through the catalogue it came from and cached the
    /// same way a local cover is — by `publication.id`, through ``serverCover(for:maxPixelSize:fetch:)``,
    /// so a reader who has seen a catalogue's grid once does not refetch it on the next launch.
    ///
    /// 11.7 / D29: `OpdsContributor`'s own rule is that no acquisition URL is kept, because
    /// such a link can carry a key in its query — so the artwork address is not kept either,
    /// and the entry is found again by the id it was filed under, through the source it came
    /// from. An unreachable catalogue answers nothing here, same as it answers nothing to
    /// the read that fills the shelf: a missing cover for an offline row is the grey,
    /// coverless well, never a retry loop.
    ///
    /// Internal, not `private`: 11.7's own regression test asserts this directly, against a
    /// registry holding one OPDS source and a stubbed transport, the way ``isOnDevice(_:)``
    /// beside it is asserted without a window. `client` is that seam — nil builds the real
    /// one, ``ServerLibrary/client(for:)``'s own way, so a test can hand this a client built
    /// over a stubbed `URLSessionConfiguration` instead, the same seam `OpdsClientTests`
    /// uses for the client itself.
    func opdsCover(
        for publication: Publication,
        maxPixelSize: Int,
        client overridden: OpdsClient? = nil
    ) async -> CGImage? {
        guard let identifier = publication.identity.serverIdentifier,
              identifier.remoteID.hasPrefix("opds:"),
              let source = registry.sources.first(where: { $0.id == identifier.sourceID }),
              let page = CataloguePage(source: source, credentials: CredentialStore())
        else { return nil }

        let client = overridden ?? ServerLibrary.client(for: page)
        return await serverCover(for: publication.id, maxPixelSize: maxPixelSize) {
            guard let feed = try? await client.feed(at: page.url, credential: page.credential),
                  let url = Self.artworkURL(forRemoteID: identifier.remoteID, in: feed.publications)
            else { throw OpdsArtworkNotFound() }
            return try await client.data(at: url, credential: page.credential)
        }
    }

    /// A Kavita chapter row's artwork, fetched through the server it came from and cached
    /// by the server and the chapter's own id — the same scoping
    /// ``HomeServerShelfCover/lockedCoverID(server:shelf:)`` uses, so a shelf card and a
    /// library row that name the same chapter share one cache entry rather than decoding
    /// the same bytes twice.
    ///
    /// 17.4: `KavitaContributor` makes a chapter row with no file location at all — the
    /// shelf path falls to Android's `ServerLibrary.cachedCover`, and this is iOS's twin of
    /// that fetch, reached from ``cover(for:maxPixelSize:)`` the same way ``opdsCover(for:maxPixelSize:client:)``
    /// is.
    func kavitaCover(
        for publication: Publication,
        maxPixelSize: Int,
        client overridden: KavitaClient? = nil,
        credentials: CredentialStore? = CredentialStore()
    ) async -> CGImage? {
        guard let identifier = publication.identity.serverIdentifier,
              identifier.remoteID.hasPrefix("chapter:"),
              let chapterID = Int(identifier.remoteID.dropFirst("chapter:".count)),
              let source = registry.sources.first(where: { $0.id == identifier.sourceID }),
              let page = KavitaPage(source: source, credentials: credentials)
        else { return nil }

        let client = overridden ?? KavitaClient(address: page.address)
        return await serverCover(for: "srv:\(page.id):chapter:\(chapterID)", maxPixelSize: maxPixelSize) {
            try await client.chapterCover(chapterID)
        }
    }

    /// The artwork link named by the entry filed under this row's id, among those a feed
    /// just listed — the thumbnail where the feed offered one, the full cover otherwise.
    ///
    /// Pulled out as a pure function so the lookup is asserted directly, with no catalogue
    /// and no network: the entry order, a `nil` thumbnail, an id nothing matches.
    ///
    /// `nonisolated`: it touches no actor state, and a synchronous test should not have to
    /// pay `LibraryModel`'s `@MainActor` isolation for a lookup over a plain array.
    nonisolated static func artworkURL(forRemoteID remoteID: String, in entries: [OpdsEntry]) -> URL? {
        entries.first(where: { "opds:\($0.id)" == remoteID }).flatMap { $0.thumbnail ?? $0.cover }
    }

    /// A server's own artwork, cached the same way a local publication's cover is.
    ///
    /// Task 22.2's own correction: `ServerShelfCover` and `HomeServerShelfCover` decode a
    /// Kavita cover's bytes every time either draws, because until now neither wrote what
    /// it decoded anywhere — a card scrolled out of view and back, a visit to Home, a
    /// relaunch, each asked the server again for bytes already decoded once. `id` is the
    /// caller's to scope: a Kavita series id and a chapter id are both small integers, two
    /// different servers answer the same one, and ``CoverCache`` hashes whatever string it
    /// is handed — so a caller that does not prefix its own kind and server folds two
    /// covers from two servers onto the one cache entry.
    public func serverCover(
        for id: String,
        maxPixelSize: Int,
        fetch: () async throws -> Data
    ) async -> CGImage? {
        let cache = CoverCache()
        if let stored = await Task.detached(priority: .utility, operation: {
            cache.image(for: id, maxPixelSize: maxPixelSize)
        }).value {
            return stored
        }

        guard let data = try? await fetch(), !data.isEmpty, let image = Self.decode(data) else {
            return nil
        }

        await Task.detached(priority: .utility, operation: {
            cache.store(image, for: id, maxPixelSize: maxPixelSize)
        }).value
        return image
    }

    /// Through `ImageIO` rather than `UIImage`, unlike ``ShelfCover``'s own decode: this
    /// method is exercised on the host, where `StoryArcKit`'s macOS target has no UIKit, and
    /// `CGImageSourceCreateWithData` decodes the same JPEG and PNG bytes Kavita answers with
    /// on both platforms.
    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
