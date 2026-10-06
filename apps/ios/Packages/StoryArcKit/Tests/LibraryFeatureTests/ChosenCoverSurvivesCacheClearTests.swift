import Foundation
import Testing

import Formats
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// Task 2.5: "a chosen cover survives a cache clear".
///
/// `cover-art` puts it in the reader's own words: "every chosen cover is still there, because
/// a chosen cover is data the reader created and not a cache". Two assertions, because either
/// alone can pass while the promise is broken — one proves the clear spares the directory,
/// and the other proves it is the directory the app actually uses.
@Suite("A chosen cover survives a cache clear")
struct ChosenCoverSurvivesCacheClearTests {

    @Test("Clearing the cache empties the cover cache and leaves the chosen covers")
    func clearCacheSparesChosenCovers() async throws {
        let root = URL.temporaryDirectory.appending(path: "chosen-cover-\(UUID().uuidString)")
        let caches = root.appending(path: "Caches")
        let data = root.appending(path: "Application Support")
        try FileManager.default.createDirectory(
            at: caches.appending(path: "covers"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // A decoded cover in the cache, and a chosen one in the store, as the app writes them.
        let cached = caches.appending(path: "covers/ab12-200.jpg")
        try Data("a decoded cover".utf8).write(to: cached)
        let overrides = CoverOverrideStore(directory: data.appending(path: "cover-overrides"))
        let chosen = try #require(overrides.store(Data("a chosen cover".utf8), for: publication))

        await StorageUsage(caches: caches, removeWebsiteData: {}).clearCache()

        #expect(!FileManager.default.fileExists(atPath: cached.path))
        #expect(FileManager.default.fileExists(atPath: chosen.path))
        #expect(overrides.data(for: publication) == Data("a chosen cover".utf8))
    }

    @Test("Chosen covers are not kept anywhere the cache clear reaches")
    func theStoreIsOutsideTheCachesDirectory() {
        let overrides = CoverOverrideStore.defaultDirectory.standardizedFileURL.path
        let caches = URL.cachesDirectory.standardizedFileURL.path
        #expect(!overrides.hasPrefix(caches.hasSuffix("/") ? caches : caches + "/"))
    }

    @Test("Removing a cover redraws every copy of the file and nothing else")
    @MainActor
    func everyCopyIsRedrawn() async {
        // The store files a chosen cover under the content digest, so two copies of one file
        // share it. Redrawing only the copy the reader acted on left the other showing the
        // old picture for the rest of the launch.
        let acted = book("a", digest: "same-bytes")
        let copy = book("b", digest: "same-bytes")
        let other = book("c", digest: "other-bytes")
        let model = LibraryModel()
        model.publications = [acted, copy, other]
        let before = [acted, copy, other].map(model.coverLoadKey(for:))

        await model.removeChosenCover(for: acted)

        let after = [acted, copy, other].map(model.coverLoadKey(for:))
        #expect(after[0] != before[0])
        #expect(after[1] != before[1], "The other copy of the same file kept its old cover.")
        #expect(after[2] == before[2])
    }

    private func book(_ name: String, digest: String) -> Publication {
        Publication(
            identity: PublicationIdentity(contentDigest: digest, normalizedPath: "/books/\(name).cbz"),
            format: .cbz,
            displayTitle: name,
            origin: .inferred
        )
    }

    private var publication: Publication {
        Publication(
            identity: PublicationIdentity(contentDigest: "digest-for-the-chosen-cover"),
            format: .m4b,
            displayTitle: "Ripped From A CD",
            origin: .inferred
        )
    }
}
