import Foundation
import Testing

@testable import StoryArcCore

/// `library-portability` / *A field this version does not know*: an unreadable record means one
/// thing on both platforms. It is dropped, the rest of the document imports, and the preview
/// counts only what lands. Android's `LibraryUnreadableRecordTest` asserts the same rows.
@Suite("One unreadable record is dropped and the rest of the document imports")
struct LibraryUnreadableRecordTests {

    private var written: LibraryDocument {
        LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            appVersion: LibraryDocumentFixture.appVersion,
            writtenAt: LibraryDocumentFixture.writtenAt
        )
    }

    /// The fixture document with its first position changed by `edit`, read back through the
    /// production decoder.
    private func decoded(editingFirstPosition edit: ([String: Any]) -> [String: Any]) throws
        -> LibraryDocument {
        var parsed = try #require(
            try JSONSerialization.jsonObject(with: LibraryDocumentCoder.encode(written))
                as? [String: Any]
        )
        var library = try #require(parsed["library"] as? [String: Any])
        var progress = try #require(library["progress"] as? [[String: Any]])
        var first = progress[0]
        first["position"] = edit(try #require(first["position"] as? [String: Any]))
        progress[0] = first
        library["progress"] = progress
        parsed["library"] = library
        return try LibraryDocumentCoder.decode(try JSONSerialization.data(withJSONObject: parsed))
    }

    private func unknownKind() throws -> LibraryDocument {
        try decoded { position in
            var changed = position
            changed["kind"] = "hologram"
            return changed
        }
    }

    @Test("A position of a kind this build does not know is dropped and the others land")
    func anUnknownKindDropsOneRecord() throws {
        let landed = LibraryImport.merging(try unknownKind(), into: LibrarySnapshot()).snapshot

        #expect(landed.progress.count == 2)
        #expect(landed.sources.sources.count == 3)
    }

    @Test("A known kind that lacks a field it needs is dropped the same way")
    func aMissingFieldDropsOneRecord() throws {
        let document = try decoded { position in
            var changed = position
            changed.removeValue(forKey: "index")
            return changed
        }

        let landed = LibraryImport.merging(document, into: LibrarySnapshot()).snapshot

        #expect(landed.progress.count == 2)
    }

    @Test("The preview counts the records the merge will keep, not the records that arrived")
    func thePlanCountsWhatLands() throws {
        let whole = LibraryImport.plan(written, onto: LibrarySnapshot())
        let dropped = LibraryImport.plan(try unknownKind(), onto: LibrarySnapshot())

        #expect(whole.progressToAdd + whole.progressToMerge == 3)
        #expect(dropped.progressToAdd + dropped.progressToMerge == 2)
    }
}
