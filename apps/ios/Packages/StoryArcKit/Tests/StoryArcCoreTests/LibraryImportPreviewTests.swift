import Foundation
import Testing

@testable import StoryArcCore

/// `library-portability` tasks 2.3, 3.3 and 6.8: what the import preview tells the reader.
///
/// The screen is a `ForEach` over ``LibraryImportPlan/previewLines``, so what the reader is
/// told is what this list holds. Android's `ImportPreviewLinesTest` asserts the same rows.
@Suite("The import preview tells the reader what will happen")
struct LibraryImportPreviewTests {

    private var document: LibraryDocument {
        LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            appVersion: LibraryDocumentFixture.appVersion,
            writtenAt: LibraryDocumentFixture.writtenAt
        )
    }

    /// A used device: the folder, the collection with one of its two members, a position of its
    /// own, and no pin and no cover.
    private var device: LibrarySnapshot {
        LibrarySnapshot(
            sources: SourceRegistry(sources: [
                Source(
                    id: LibraryDocumentFixture.folderID,
                    displayName: "Shelf",
                    kind: .localFolder,
                    locator: "/Books/Shelf"
                ),
            ]),
            shelves: Shelves(
                collections: [
                    PublicationCollection(
                        id: LibraryDocumentFixture.collectionID,
                        name: "Image Comics",
                        members: ["path:/a.cbz"]
                    ),
                ]
            ),
            progress: [
                ReadingProgress(
                    identity: PublicationIdentity(contentDigest: "d1", normalizedPath: "/a.cbz"),
                    position: .page(index: 30, of: 40),
                    updatedAt: Date(timeIntervalSince1970: 1_767_200_000)
                ),
            ]
        )
    }

    @Test("Every change is a line, and the change to what the app trusts comes first")
    func everyChangeIsALine() {
        let lines = LibraryImport.plan(document, onto: device).previewLines

        #expect(lines == [
            .certificatePins([CertificatePinNotice(host: "nas.local", sourceName: "Comics NAS")]),
            .sourcesToAdd(["Comics NAS", "Kavita"]),
            .sourcesNeedingSignIn(["Comics NAS", "Kavita"]),
            .shelvesToAdd(["Crossover"]),
            .shelvesMerged([ImportedShelf(name: "Image Comics", membersAdded: 1)]),
            .progress(add: 2, merge: 1),
            .themes(2),
            .covers(1),
            .settingsChange,
        ])
    }

    @Test("The pin line names the host and the source it arrived with")
    func thePinLineNamesBoth() {
        let lines = LibraryImport.plan(document, onto: device).previewLines
        let pins = lines.compactMap { line -> [CertificatePinNotice]? in
            if case let .certificatePins(pins) = line { return pins }
            return nil
        }

        #expect(pins == [[CertificatePinNotice(host: "nas.local", sourceName: "Comics NAS")]])
    }

    @Test("A pin the device already holds is not a line")
    func aHeldPinIsNotALine() {
        var pinned = device
        pinned.certificatePins = ["nas.local": ["AB:CD:EF:01"]]

        let lines = LibraryImport.plan(document, onto: pinned).previewLines

        #expect(!lines.contains { if case .certificatePins = $0 { true } else { false } })
    }

    @Test("The merge line states how many members each shelf gains")
    func theMergeLineCountsMembers() {
        let lines = LibraryImport.plan(document, onto: device).previewLines

        #expect(lines.contains(.shelvesMerged([ImportedShelf(name: "Image Comics", membersAdded: 1)])))
    }

    @Test("A plan with nothing in it says so instead of showing an empty list")
    func anEmptyPlanSaysNothingIsNew() {
        #expect(LibraryImportPlan().previewLines == [.nothingNew])
    }

    @Test("A count of zero is not a line")
    func zeroIsNotALine() {
        let plan = LibraryImportPlan(progressToAdd: 0, progressToMerge: 3, themeEntriesToAdd: 0)

        #expect(plan.previewLines == [.progress(add: 0, merge: 3)])
    }
}
