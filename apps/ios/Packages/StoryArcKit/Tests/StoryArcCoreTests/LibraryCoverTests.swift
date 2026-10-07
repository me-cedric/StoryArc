import Foundation
import Testing

@testable import StoryArcCore

/// `library-portability` tasks 2.1 and 6.7: a cover the reader chose travels in the document.
/// Android's `LibraryCoverTest` asserts the same rows against the same fixture.
@Suite("A chosen cover travels in the document")
struct LibraryCoverTests {

    private var document: LibraryDocument {
        LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            appVersion: LibraryDocumentFixture.appVersion,
            writtenAt: LibraryDocumentFixture.writtenAt
        )
    }

    private func document(carrying covers: [DocumentCover]) -> LibraryDocument {
        var changed = document
        changed.library.covers = covers
        return changed
    }

    @Test("Export writes each chosen cover as its key and its image in base64")
    func exportWritesTheCover() {
        #expect(document.library.covers == [
            DocumentCover(
                key: LibraryDocumentFixture.coverKey,
                image: LibraryDocumentFixture.coverImage.base64EncodedString()
            ),
        ])
    }

    @Test("A cover survives a write and a read through the coder, byte for byte")
    func coverSurvivesTheCoder() throws {
        let read = try LibraryDocumentCoder.decode(LibraryDocumentCoder.encode(document))
        let landed = LibraryImport.merging(read, into: LibrarySnapshot()).snapshot

        #expect(landed.covers == [
            ChosenCover(key: LibraryDocumentFixture.coverKey, image: LibraryDocumentFixture.coverImage),
        ])
    }

    @Test("A cover the device already holds under the same key stands")
    func theDevicesOwnCoverStands() {
        var device = LibrarySnapshot()
        device.covers = [ChosenCover(key: LibraryDocumentFixture.coverKey, image: Data([1, 2, 3]))]

        let landed = LibraryImport.merging(document, into: device).snapshot

        #expect(landed.covers == device.covers)
        #expect(LibraryImport.plan(document, onto: device).coversToAdd == 0)
    }

    @Test("The preview counts a cover that will arrive")
    func thePlanCountsTheCover() {
        #expect(LibraryImport.plan(document, onto: LibrarySnapshot()).coversToAdd == 1)
    }

    @Test("An image that is not base64, is empty or is over the ceiling is dropped, and only it")
    func unreadableCoversAreDropped() {
        let tooBig = Data(count: LibraryImport.maximumCoverBytes + 1).base64EncodedString()
        let carrying = document(carrying: [
            DocumentCover(key: "sha:good", image: LibraryDocumentFixture.coverImage.base64EncodedString()),
            DocumentCover(key: "sha:notbase64", image: "***"),
            DocumentCover(key: "sha:empty", image: ""),
            DocumentCover(key: "sha:big", image: tooBig),
        ])

        let landed = LibraryImport.merging(carrying, into: LibrarySnapshot()).snapshot

        #expect(landed.covers.map(\.key) == ["sha:good"])
        #expect(landed.sources.sources.count == 3)
        #expect(LibraryImport.plan(carrying, onto: LibrarySnapshot()).coversToAdd == 1)
    }

    @Test("An image exactly at the ceiling is kept")
    func theCeilingItselfIsKept() {
        let atCeiling = Data(count: LibraryImport.maximumCoverBytes).base64EncodedString()

        let landed = LibraryImport.merging(
            document(carrying: [DocumentCover(key: "sha:edge", image: atCeiling)]),
            into: LibrarySnapshot()
        ).snapshot

        #expect(landed.covers.map(\.key) == ["sha:edge"])
    }

    @Test("The key a publication's cover is filed under is its digest, else its stable identifier")
    func theKeyRule() {
        #expect(PublicationIdentity(contentDigest: "d1", normalizedPath: "/a.cbz").coverOverrideKey
            == "sha:d1")
        #expect(PublicationIdentity(normalizedPath: "/a.cbz").coverOverrideKey == "path:/a.cbz")
    }
}
