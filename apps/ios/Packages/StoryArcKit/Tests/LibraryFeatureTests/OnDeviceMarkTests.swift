import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// Which covers carry the downloaded mark.
///
/// `design.md` asks the grid for "downloaded state as a small filled mark in one corner" and
/// neither platform drew one, so the question behind it had never been asked in code either.
/// The answer has to be cheap enough to ask once per visible cell on every redraw, which is
/// why it is a path comparison and not a read of the download store — and a path comparison
/// is exactly the kind of thing that is quietly wrong at a boundary.
///
/// Real directories, no mock: the whole assertion is about where a file actually sits.
@Suite("On-device mark")
@MainActor
struct OnDeviceMarkTests {

    /// A throwaway directory, standing in for a place on the device.
    private func directory(_ name: String) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A publication that claims to live at `url`, on a model whose store is `store`.
    private func model(holding url: URL, downloadedInto store: DownloadStore) -> LibraryModel {
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: url.path),
            format: .cbz,
            displayTitle: "Fixture",
            origin: .inferred
        )
        let model = LibraryModel(downloadStore: store)
        model.publications = [publication]
        model.locations[publication.id] = url
        return model
    }

    @Test("A publication in the app's own store is marked")
    func downloadedIsMarked() throws {
        let downloads = try directory("downloads")
        defer { try? FileManager.default.removeItem(at: downloads) }

        let store = DownloadStore(directory: downloads)
        let model = model(holding: downloads.appending(path: "kept.cbz"), downloadedInto: store)

        #expect(model.isOnDevice(try #require(model.publications.first)))
    }

    @Test("A publication in a folder the reader picked is not marked")
    func scannedIsNotMarked() throws {
        // The distinction the mark exists for. A picked folder is on the device too, right
        // up until the card is pulled or the share is unmounted — which is what
        // `unavailableFolders` is for. Only a copy the app holds carries the promise
        // `offline-downloads` makes, so only that copy earns the badge.
        let downloads = try directory("downloads")
        let picked = try directory("picked")
        defer {
            try? FileManager.default.removeItem(at: downloads)
            try? FileManager.default.removeItem(at: picked)
        }

        let store = DownloadStore(directory: downloads)
        let model = model(holding: picked.appending(path: "scanned.cbz"), downloadedInto: store)

        #expect(!model.isOnDevice(try #require(model.publications.first)))
    }

    @Test("A sibling folder whose name merely starts with the store's is not marked")
    func siblingPrefixIsNotMarked() throws {
        // The boundary a bare `hasPrefix` gets wrong. `…/downloads-abc/old` starts with
        // `…/downloads-abc` — the trailing separator is the whole reason the comparison
        // is not written the obvious way.
        let downloads = try directory("downloads")
        let sibling = URL(fileURLWithPath: downloads.path + "-old")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: downloads)
            try? FileManager.default.removeItem(at: sibling)
        }

        let store = DownloadStore(directory: downloads)
        let model = model(holding: sibling.appending(path: "elsewhere.cbz"), downloadedInto: store)

        #expect(!model.isOnDevice(try #require(model.publications.first)))
    }

    @Test("A library with no download store marks nothing")
    func noStoreMarksNothing() throws {
        // The app layer may hand the model no store at all, and a shelf that badged every
        // cover because the comparison had nothing to compare against would be worse than
        // one that badges none.
        let picked = try directory("picked")
        defer { try? FileManager.default.removeItem(at: picked) }

        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: picked.appending(path: "a.cbz").path),
            format: .cbz,
            displayTitle: "Fixture",
            origin: .inferred
        )
        let model = LibraryModel()
        model.publications = [publication]
        model.locations[publication.id] = picked.appending(path: "a.cbz")

        #expect(!model.isOnDevice(publication))
    }
}
