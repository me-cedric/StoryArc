import Foundation
import Testing

@testable import StoryArcCore

/// `library-portability` / *One versioned document*, row by row.
@Suite("A library document declares its version and survives a round trip")
struct LibraryDocumentTests {

    private func document() -> LibraryDocument {
        LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            appVersion: LibraryDocumentFixture.appVersion,
            writtenAt: LibraryDocumentFixture.writtenAt
        )
    }

    @Test("The document declares a version, an app version, a platform and a moment")
    func declaresWhatItIs() throws {
        let written = document()

        #expect(written.formatVersion == 1)
        #expect(written.appVersion == "10.14.0")
        #expect(written.writtenBy == WritingPlatform.ios)
        #expect(written.writtenAt == LibraryDocumentFixture.writtenAt)
        // Filled only when the reader asks to carry secrets: see `LibraryDocument.secrets`.
        #expect(written.secrets == nil)
    }

    @Test("This platform still writes the document committed under packages/test-fixtures")
    func writesTheCommittedDocument() throws {
        // The wire is pinned here rather than inferred from the Swift types, because every
        // enum in the body is written as its raw value — so a rename nobody thought of as a
        // wire change would change every file this app has written, and nothing else would
        // notice. Android reads this exact file.
        let written = try LibraryDocumentCoder.encode(document())
        let committed = try LibraryDocumentFixture.document(named: "written-by-ios.json")

        #expect(String(bytes: written, encoding: .utf8)
            == String(bytes: committed, encoding: .utf8))
    }

    @Test("A document this platform wrote reads back as the library that went in")
    func roundTripsThroughItsOwnCoder() throws {
        let written = try LibraryDocumentCoder.encode(document())

        #expect(try LibraryDocumentCoder.decode(written) == document())
    }

    @Test("A field this version does not know is ignored and the rest is imported")
    func unknownFieldSurvivesADecode() throws {
        var parsed = try #require(
            try JSONSerialization.jsonObject(
                with: LibraryDocumentCoder.encode(document())
            ) as? [String: Any]
        )
        parsed["somethingTheNextVersionAdded"] = ["a": 1]
        var library = try #require(parsed["library"] as? [String: Any])
        library["aStoreThisBuildHasNever"] = ["x"]
        parsed["library"] = library

        let read = try LibraryDocumentCoder.decode(
            try JSONSerialization.data(withJSONObject: parsed)
        )

        #expect(read == document())
    }

    @Test("A document written by a platform this build has never heard of still reads and imports")
    func anUnknownWritingPlatformIsNotFatal() throws {
        var parsed = try #require(
            try JSONSerialization.jsonObject(
                with: LibraryDocumentCoder.encode(document())
            ) as? [String: Any]
        )
        parsed["writtenBy"] = "windows"

        let read = try LibraryDocumentCoder.decode(
            try JSONSerialization.data(withJSONObject: parsed)
        )
        let landed = LibraryImport.merging(read, into: LibrarySnapshot()).snapshot

        #expect(read.writtenBy == "windows")
        #expect(landed.sources.sources.count == LibraryDocumentFixture.snapshot.sources.sources.count)
    }

    @Test("A document over the size limit is refused by name, and one at the limit reads")
    func anOversizedDocumentIsRefused() throws {
        let bytes = try LibraryDocumentCoder.encode(document())

        #expect(throws: LibraryDocumentFailure.tooLarge(found: bytes.count, limit: bytes.count - 1)) {
            try LibraryDocumentCoder.decode(bytes, limit: bytes.count - 1)
        }
        #expect(try LibraryDocumentCoder.decode(bytes, limit: bytes.count) == document())
    }

    @Test("The size is checked before the parse, so bytes that are not JSON are named too large")
    func theSizeIsCheckedBeforeTheParse() {
        // Not a document at all. Were the parse first, this would be `notALibraryDocument`.
        let oversized = Data(count: LibraryDocumentCoder.maximumBytes + 1)

        #expect(throws: LibraryDocumentFailure.tooLarge(
            found: oversized.count,
            limit: LibraryDocumentCoder.maximumBytes
        )) {
            try LibraryDocumentCoder.decode(oversized)
        }
        #expect(LibraryDocumentCoder.declaredVersion(of: oversized) == nil)
    }

    @Test("A newer document is refused by name and nothing is read out of it")
    func aNewerDocumentIsRefused() throws {
        var parsed = try #require(
            try JSONSerialization.jsonObject(
                with: LibraryDocumentCoder.encode(document())
            ) as? [String: Any]
        )
        parsed["formatVersion"] = 99
        let bytes = try JSONSerialization.data(withJSONObject: parsed)

        #expect(throws: LibraryDocumentFailure.newerThanThisApp(found: 99, understood: 1)) {
            try LibraryDocumentCoder.decode(bytes)
        }
    }

    @Test("Bytes that are not a library document are refused as such")
    func somethingElseEntirely() {
        #expect(throws: LibraryDocumentFailure.notALibraryDocument) {
            try LibraryDocumentCoder.decode(Data("{\"hello\":1}".utf8))
        }
    }

    @Test("An older document is migrated through each transform in order")
    func anOlderDocumentIsMigrated() throws {
        // A fake version 0, proving the chain runs. The shipped chain is empty — version 1 is
        // the first — so without an injected transform there would be nothing to assert and
        // the second version would be the first to find out whether this worked.
        var parsed = try #require(
            try JSONSerialization.jsonObject(
                with: LibraryDocumentCoder.encode(document())
            ) as? [String: Any]
        )
        parsed["formatVersion"] = 0
        parsed["appVersion"] = "before the transform"

        let read = try LibraryDocumentCoder.decode(
            try JSONSerialization.data(withJSONObject: parsed),
            transforms: [
                LibraryDocumentTransform(from: 0) { older in
                    var newer = older
                    newer["appVersion"] = "after the transform"
                    return newer
                },
            ]
        )

        #expect(read.formatVersion == 1)
        #expect(read.appVersion == "after the transform")
    }

    @Test("An older document with no transform to reach this version is refused")
    func aMissingTransformIsRefused() throws {
        var parsed = try #require(
            try JSONSerialization.jsonObject(
                with: LibraryDocumentCoder.encode(document())
            ) as? [String: Any]
        )
        parsed["formatVersion"] = 0

        #expect(throws: LibraryDocumentFailure.noMigrationPath(from: 0)) {
            try LibraryDocumentCoder.decode(try JSONSerialization.data(withJSONObject: parsed))
        }
    }

    @Test("The version is readable without decoding the document")
    func theVersionIsReadableOnItsOwn() throws {
        let bytes = try LibraryDocumentCoder.encode(document())

        #expect(LibraryDocumentCoder.declaredVersion(of: bytes) == 1)
        #expect(LibraryDocumentCoder.declaredVersion(of: Data("not json".utf8)) == nil)
    }
}

/// design.md's table: the five records whose stores disagree on the wire.
///
/// Written by Android's encoder and read by this one. The file under
/// `packages/test-fixtures/library/` is the only thing the two suites share, which is the
/// point — neither platform can privately redefine what the document says.
@Suite("The five disagreements reconcile at the boundary")
struct LibraryDocumentBoundaryTests {

    private func readAndroidsDocument() throws -> LibraryDocument {
        try LibraryDocumentCoder.decode(
            LibraryDocumentFixture.document(named: "written-by-android.json")
        )
    }

    @Test("A source timestamp Android wrote as epoch millis arrives as a moment")
    func sourceTimestamp() throws {
        let source = try #require(
            readAndroidsDocument().library.sources
                .first { $0.id == LibraryDocumentFixture.networkShareID }
        )

        #expect(source.lastSuccessfulSync == Date(timeIntervalSince1970: 1_767_139_445))
    }

    @Test("A source kind Android wrote as LOCAL_FOLDER arrives as a kind this build knows")
    func sourceKind() throws {
        let kinds = try readAndroidsDocument().library.sources.map(\.kind)

        #expect(kinds == ["networkShare", "localFolder", "kavitaServer"])
        #expect(kinds.allSatisfy { SourceKind(rawValue: $0) != nil })
    }

    @Test("A shelf cover arrives under the one key both platforms agreed")
    func shelfCoverKey() throws {
        let collection = try #require(readAndroidsDocument().library.collections.first)

        #expect(collection.coverMemberId == "path:/b.cbz")
    }

    @Test("A reading position Android wrote as flat columns arrives as all three kinds")
    func readingPosition() throws {
        let positions = try readAndroidsDocument().library.progress.map(\.position.position)

        #expect(positions == [
            .page(index: 12, of: 40),
            .reflowable(progression: 0.375, locator: "{\"href\":\"ch3\"}"),
            .listening(part: 2, partCount: 9, offset: 61.5, of: 600),
        ])
    }

    @Test("Pinned shelves arrive as a list of the tokens both platforms already shared")
    func pinnedShelves() throws {
        let pins = try readAndroidsDocument().library.pinnedShelves

        #expect(
            Set(pins.compactMap(ShelfPin.init(token:)))
                == [
                    .collection(LibraryDocumentFixture.collectionID),
                    .list(LibraryDocumentFixture.listID),
                ]
        )
    }

    @Test("Every other record Android wrote is the library this platform would have written")
    func everythingElse() throws {
        let theirs = try readAndroidsDocument()
        let mine = LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            appVersion: LibraryDocumentFixture.appVersion,
            writtenAt: LibraryDocumentFixture.writtenAt
        )

        // The envelope differs by the platform that wrote it, and by nothing else.
        #expect(theirs.writtenBy == WritingPlatform.android)
        #expect(theirs.library.certificatePins == mine.library.certificatePins)
        #expect(theirs.library.collections == mine.library.collections)
        #expect(theirs.library.readingLists == mine.library.readingLists)
        #expect(theirs.library.readingThemes == mine.library.readingThemes)
        #expect(theirs.library.progress == mine.library.progress)
        #expect(theirs.library.covers == mine.library.covers)
        // Android carries one setting this platform does not have, which decodes away.
        #expect(theirs.library.settings == mine.library.settings)
    }

    @Test("A document Android wrote imports onto an empty device, record kind by record kind")
    func importingAndroidsDocument() throws {
        // Task 4.1's round trip, in the direction this platform can assert: Android's
        // encoder wrote the file, this decoder read it, and this importer landed it.
        let landed = LibraryImport.merging(try readAndroidsDocument(), into: LibrarySnapshot())
            .snapshot

        #expect(landed.sources.sources.map(\.kind) == [.networkShare, .localFolder, .kavitaServer])
        #expect(landed.sources.sources.first?.lastSuccessfulSync
            == Date(timeIntervalSince1970: 1_767_139_445))
        #expect(landed.certificatePins == ["nas.local": ["AB:CD:EF:01"]])
        #expect(landed.shelves.collections.first?.coverMemberID == "path:/b.cbz")
        #expect(landed.shelves.lists.first?.entries == ["path:/b.cbz", "path:/a.cbz"])
        #expect(Set(landed.pinnedShelves.tokens)
            == Set(LibraryDocumentFixture.snapshot.pinnedShelves.tokens))
        #expect(landed.settings == LibraryDocumentFixture.snapshot.settings)
        #expect(landed.themes.default(for: .reflowable).values.fontSize == .large)
        #expect(landed.themes.theme(for: .fixedLayout, shelf: "Bone").fit == .width)
        #expect(landed.themes.customPalette?.name == "Midnight")
        #expect(landed.progress.map(\.position) == [
            .page(index: 12, of: 40),
            .reflowable(progression: 0.375, locator: "{\"href\":\"ch3\"}"),
            .listening(part: 2, partCount: 9, offset: 61.5, of: 600),
        ])
        // Every source that held a secret arrives without one and asks for it.
        #expect(landed.sources.sources.allSatisfy { $0.credentialReference == nil })
        // The cover Android's reader chose arrives as the same bytes, under the same key.
        #expect(landed.covers == [
            ChosenCover(key: LibraryDocumentFixture.coverKey, image: LibraryDocumentFixture.coverImage),
        ])
    }
}
