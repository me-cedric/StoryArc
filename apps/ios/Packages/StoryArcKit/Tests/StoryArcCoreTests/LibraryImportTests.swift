import Foundation
import Testing

@testable import StoryArcCore

/// `library-portability` / *Import merges*, row by row.
///
/// Android's `LibraryImportTest` asserts the same rows against the same library, so neither
/// platform can privately decide what a merge means.
@Suite("An import merges into what the device already holds")
struct LibraryImportTests {

    private var document: LibraryDocument {
        LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            appVersion: LibraryDocumentFixture.appVersion,
            writtenAt: LibraryDocumentFixture.writtenAt
        )
    }

    /// A device that has been used: one of the three sources already, the collection with one
    /// of its two members, and this device's own reading further on than the document's.
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
                // Never synchronised with anything, which is the case task 1.4 fixed and the
                // case every new phone is in.
                ReadingProgress(
                    identity: PublicationIdentity(contentDigest: "d1", normalizedPath: "/a.cbz"),
                    position: .page(index: 30, of: 40),
                    updatedAt: Date(timeIntervalSince1970: 1_767_200_000)
                ),
            ]
        )
    }

    // MARK: The preview

    @Test("The plan states what will be added, what will be merged and what needs a sign-in")
    func thePlanStatesWhatWillHappen() {
        let plan = LibraryImport.plan(document, onto: device)

        #expect(plan.sourcesToAdd == ["Comics NAS", "Kavita"])
        #expect(plan.sourcesNeedingSignIn == ["Comics NAS", "Kavita"])
        #expect(plan.shelvesToAdd == ["Crossover"])
        #expect(plan.shelvesToMerge == [ImportedShelf(name: "Image Comics", membersAdded: 1)])
        #expect(plan.progressToAdd == 2)
        #expect(plan.progressToMerge == 1)
        #expect(plan.settingsWillChange)
        #expect(plan.themeEntriesToAdd == 2)
    }

    @Test("Planning changes nothing on the device")
    func planningChangesNothing() {
        let before = device
        _ = LibraryImport.plan(document, onto: before)

        #expect(before == device)
    }

    // MARK: Sources

    @Test("An imported source arrives without a secret and is listed as needing one")
    func anImportedSourceNeedsASignIn() {
        let merged = LibraryImport.merging(document, into: device).snapshot
        let arrived = merged.sources.sources.first { $0.id == LibraryDocumentFixture.networkShareID }

        #expect(arrived?.displayName == "Comics NAS")
        // `sources` keeps the library browsable while a source is unreachable, so the source
        // is listed with no secret rather than withheld until one is supplied.
        #expect(arrived?.credentialReference == nil)
        #expect(arrived?.locator == "smb://reader@nas.local/comics")
    }

    @Test("A source the device already has is left exactly as it was")
    func anExistingSourceIsUntouched() {
        let merged = LibraryImport.merging(document, into: device).snapshot

        #expect(merged.sources.sources.first { $0.id == LibraryDocumentFixture.folderID }
            == device.sources.sources.first)
    }

    @Test("A source this device is already signed in to is not listed as needing a sign-in")
    func anAlreadySignedInSourceIsNotListed() {
        var signedIn = device
        signedIn.sources = signedIn.sources.adding(
            Source(
                id: LibraryDocumentFixture.networkShareID,
                displayName: "Comics NAS",
                kind: .networkShare,
                credentialReference: "keychain:already-here"
            )
        )

        #expect(LibraryImport.plan(document, onto: signedIn).sourcesNeedingSignIn == ["Kavita"])
    }

    // MARK: Certificate pins

    @Test("A pin is named with the source it arrived with rather than applied silently")
    func aPinIsNamed() {
        let plan = LibraryImport.plan(document, onto: device)

        #expect(plan.certificatePinsToAdd
            == [CertificatePinNotice(host: "nas.local", sourceName: "Comics NAS")])
    }

    @Test("A pin the device already holds is not announced again")
    func aPinAlreadyHeld() {
        var pinned = device
        pinned.certificatePins = ["nas.local": ["AB:CD:EF:01"]]

        #expect(LibraryImport.plan(document, onto: pinned).certificatePinsToAdd.isEmpty)
    }

    @Test("Pins merge rather than replace, so a pin accepted here survives the import")
    func pinsMerge() {
        var pinned = device
        pinned.certificatePins = ["nas.local": ["99:88"]]

        let merged = LibraryImport.merging(document, into: pinned).snapshot

        #expect(merged.certificatePins["nas.local"] == ["99:88", "AB:CD:EF:01"])
    }

    // MARK: Shelves

    @Test("A collection on both sides merges its members and keeps the device's cover choice")
    func aCollectionMerges() {
        let merged = LibraryImport.merging(document, into: device).snapshot
        let collection = merged.shelves.collections.first { $0.id == LibraryDocumentFixture.collectionID }

        #expect(collection?.members == ["path:/a.cbz", "path:/b.cbz"])
        // The device had chosen no cover, so the document's choice fills the gap.
        #expect(collection?.coverMemberID == "path:/b.cbz")
    }

    @Test("A reading list the device does not have arrives whole, in its own order")
    func aReadingListArrives() {
        let merged = LibraryImport.merging(document, into: device).snapshot

        #expect(merged.shelves.lists.first?.entries == ["path:/b.cbz", "path:/a.cbz"])
    }

    @Test("A pin on a shelf survives alongside the device's own pins")
    func pinnedShelvesMerge() {
        let merged = LibraryImport.merging(document, into: device).snapshot

        #expect(Set(merged.pinnedShelves.tokens)
            == Set(LibraryDocumentFixture.snapshot.pinnedShelves.tokens))
    }

    // MARK: Reading progress

    @Test("On a device that never synced, the furthest position wins and nothing is flagged")
    func progressOnADeviceThatNeverSynced() {
        let result = LibraryImport.merging(document, into: device)
        let record = result.snapshot.progress.first {
            $0.identity.matches(PublicationIdentity(contentDigest: "d1"))
        }

        // The device read to page 30 and the document stopped at 12. Without task 1.4 this
        // took the conflict branch and told the reader about a disagreement that was not one.
        #expect(record?.position == .page(index: 30, of: 40))
        #expect(result.conflicts.isEmpty)
    }

    @Test("A document further on than the device wins, on a device that never synced")
    func theDocumentCanBeFurther() {
        var behind = device
        behind.progress = [
            ReadingProgress(
                identity: PublicationIdentity(contentDigest: "d1", normalizedPath: "/a.cbz"),
                position: .page(index: 2, of: 40),
                updatedAt: Date(timeIntervalSince1970: 1_767_200_000)
            ),
        ]

        let result = LibraryImport.merging(document, into: behind)
        let record = result.snapshot.progress.first {
            $0.identity.matches(PublicationIdentity(contentDigest: "d1"))
        }

        #expect(record?.position == .page(index: 12, of: 40))
        #expect(result.conflicts.isEmpty)
    }

    @Test("Finished stays finished")
    func finishedIsSticky() {
        let merged = LibraryImport.merging(document, into: device).snapshot
        let record = merged.progress.first {
            $0.identity.matches(PublicationIdentity(contentDigest: "d2"))
        }

        #expect(record?.isFinished == true)
    }

    @Test("A position the device does not hold at all arrives")
    func aNewPositionArrives() {
        let merged = LibraryImport.merging(document, into: device).snapshot

        #expect(merged.progress.count == 3)
    }

    @Test("An imported record carries no watermark, because the document carries none")
    func anImportedRecordHasNoWatermark() {
        let merged = LibraryImport.merging(document, into: device).snapshot
        let record = merged.progress.first {
            $0.identity.matches(PublicationIdentity(contentDigest: "d2"))
        }

        // A watermark says what *this* device last exchanged with a server. Carrying one in
        // would tell the device it had synchronised when it never had.
        #expect(record?.syncedPosition == nil)
    }

    @Test("Both sides moved since a real watermark, so the reader is told once")
    func aGenuineConflictIsStillReported() {
        var synced = device
        synced.progress = [
            ReadingProgress(
                identity: PublicationIdentity(contentDigest: "d1", normalizedPath: "/a.cbz"),
                position: .page(index: 30, of: 40),
                updatedAt: Date(timeIntervalSince1970: 1_767_200_000),
                syncedPosition: .page(index: 1, of: 40)
            ),
        ]

        let result = LibraryImport.merging(document, into: synced)

        #expect(result.conflicts.count == 1)
        #expect(result.conflicts.first?.resolved.position == .page(index: 30, of: 40))
        #expect(result.conflicts.first?.discarded == .page(index: 12, of: 40))
    }

    // MARK: Themes

    @Test("A theme the device has chosen stands; one it has never chosen arrives")
    func themesMerge() {
        var themed = device
        themed.themes = ShelfMemory().settingDefault(
            ShelfSettings(theme: ReadingTheme(preset: .bold)),
            for: .reflowable
        )

        let merged = LibraryImport.merging(document, into: themed).snapshot

        #expect(merged.themes.default(for: .reflowable).theme.preset == .bold)
        #expect(merged.themes.remembers(scope: .fixedLayout, shelf: "Bone"))
        #expect(merged.themes.theme(for: .fixedLayout, shelf: "Bone").fit == .width)
    }

    @Test("The reader's own palette survives an import that carries another")
    func theCustomPaletteIsNotOverwritten() {
        var themed = device
        themed.themes.customPalette = ReaderPalette(
            name: "Mine",
            background: "#FFFFFF",
            foreground: "#000000"
        )

        let merged = LibraryImport.merging(document, into: themed).snapshot

        #expect(merged.themes.customPalette?.name == "Mine")
    }
}
