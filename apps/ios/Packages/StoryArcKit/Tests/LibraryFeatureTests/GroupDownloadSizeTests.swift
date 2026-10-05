import Foundation
import Testing

@testable import LibraryFeature
import Catalogue
import StoryArcCore

/// What a group download states before it starts — `offline-downloads` 6.4.
///
/// *Downloading a collection or reading list* requires the app to state "the item count and
/// total size". The size was measured from files on disk, and a member this device has never
/// fetched has no file: ten catalogue rows were confirmed as weighing nothing and then fetched
/// hundreds of megabytes. The feed states a length for each of them, and that is now what is
/// counted. Android asserts the same in `GroupDownloadSizeTest.kt`.
@Suite("What a group download says it weighs")
@MainActor
struct GroupDownloadSizeTests {
    private let source = UUID()

    private func entry(length: Int64?) -> OpdsEntry {
        OpdsEntry(
            id: "hl09",
            title: "Harbour Lights 09",
            acquisitions: [
                OpdsAcquisition(
                    href: URL(string: "https://example.invalid/hl09.epub")!,
                    mediaType: "application/epub+zip",
                    kind: .open,
                    length: length
                ),
            ]
        )
    }

    @Test("A catalogue row carries the size the feed stated")
    func rowCarriesTheStatedSize() throws {
        let row = try #require(OpdsContributor.publication(source: source, entry: entry(length: 8_400_000)))

        #expect(row.fileSize == 8_400_000)
    }

    @Test("A catalogue row that states no length is unknown rather than zero")
    func rowWithNoStatedSizeIsUnknown() throws {
        let row = try #require(OpdsContributor.publication(source: source, entry: entry(length: nil)))

        #expect(row.fileSize == nil)
    }

    @Test("A member with no file on the device weighs what the server stated")
    func memberWithNoFileWeighsWhatTheServerStated() throws {
        let row = try #require(OpdsContributor.publication(source: source, entry: entry(length: 8_400_000)))
        let model = LibraryModel()
        model.adopt(row, from: source)
        let adopted = try #require(model.publications.first)
        // No location for it: this device has never fetched from that catalogue.
        #expect(model.location(of: adopted) == nil)

        #expect(model.bytesOnDisk(of: [adopted.id]) == 8_400_000)
    }
}
