import Foundation
import Testing

import StoryArcCore
@testable import Formats

/// `library-portability` task 6.7: an export has to name the covers a reader chose, and the
/// store files them under a hash. These are the rows that make the name recoverable. Android's
/// `CoverOverrideKeyTest` is the twin.
@Suite("The cover store names what it holds")
struct CoverOverrideKeyTests {

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cover-keys-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func publication(digest: String?, path: String) -> Publication {
        Publication(
            identity: PublicationIdentity(contentDigest: digest, normalizedPath: path),
            format: .cbz,
            displayTitle: path,
            origin: .inferred
        )
    }

    @Test("A cover filed by key is named, with its image, by a store that never saw the publication")
    func aFiledCoverIsNamed() throws {
        let directory = try folder()
        CoverOverrideStore(directory: directory).store(Data([7, 7]), forKey: "sha:d1")

        let chosen = CoverOverrideStore(directory: directory).chosen(including: [])

        #expect(chosen == [ChosenCover(key: "sha:d1", image: Data([7, 7]))])
    }

    @Test("A cover chosen through the publication API is named by the same key an export uses")
    func thePublicationAPIAndTheKeyAPIAgree() throws {
        let directory = try folder()
        let store = CoverOverrideStore(directory: directory)
        let book = publication(digest: "d1", path: "/a.cbz")

        _ = store.store(Data([1]), for: book)

        #expect(store.chosen(including: []).map(\.key) == [book.identity.coverOverrideKey])
        #expect(store.image(forKey: "sha:d1") == Data([1]))
        #expect(store.data(for: book) == Data([1]))
    }

    @Test("A cover chosen before keys were filed is found when its key is a candidate")
    func aCoverWithNoKeyFileIsFoundByCandidate() throws {
        let directory = try folder()
        let store = CoverOverrideStore(directory: directory)
        store.store(Data([9]), forKey: "sha:old")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "key" {
            try FileManager.default.removeItem(at: file)
        }

        #expect(store.chosen(including: []).isEmpty)
        #expect(store.chosen(including: ["sha:old", "sha:never-chosen"]).map(\.key) == ["sha:old"])
    }

    @Test("Removing a cover removes its image and the file that names it")
    func removingForgetsTheName() throws {
        let directory = try folder()
        let store = CoverOverrideStore(directory: directory)
        store.store(Data([1]), forKey: "sha:d1")

        store.remove(forKey: "sha:d1")

        #expect(store.chosen(including: []).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
