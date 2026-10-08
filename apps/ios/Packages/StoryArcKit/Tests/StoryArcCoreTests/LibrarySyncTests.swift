import Foundation
import Testing
@testable import StoryArcCore

/// `library-sync` tasks 3.1, 3.6 and 3.7: read-merge-write, a provider's conflicted copy, and no
/// Kavita position in the document. Android's `LibrarySyncTest` makes the same claims.
struct LibrarySyncTests {

    private let book = PublicationIdentity(contentDigest: "d1")
    private let other = PublicationIdentity(contentDigest: "d2")
    private let shelfA = LibraryDocumentFixture.fixed("AAAAAAAA-0000-0000-0000-000000000001")
    private let shelfB = LibraryDocumentFixture.fixed("BBBBBBBB-0000-0000-0000-000000000002")

    private func shelf(_ id: UUID, _ name: String, at second: TimeInterval) -> LibrarySnapshot {
        LibrarySnapshot(shelves: Shelves(collections: [
            PublicationCollection(id: id, name: name, members: ["m:\(name)"], changedAt: moment(second)),
        ]))
    }

    @Test func twoDevicesThatWriteInTurnBothKeepEveryRecord() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a", shelf(shelfA, "A", at: 1))
        let deviceB = SyncDevice("device-b", shelf(shelfB, "B", at: 2))
        deviceB.read(book, page: 7, at: 3)

        try await deviceA.sync(place, at: 10)
        try await deviceB.sync(place, at: 11)
        try await deviceA.sync(place, at: 12)

        for device in [deviceA, deviceB] {
            #expect(Set(device.library.shelves.collections.map(\.id)) == [shelfA, shelfB])
            #expect(device.position(book)?.position == .page(index: 7, of: 100))
        }
        #expect(try place.document().library.collections.count == 2)
    }

    @Test func aWriteThatFindsTheDocumentChangedReadsItAgainAndMerges() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a", shelf(shelfA, "A", at: 1))
        let deviceB = SyncDevice("device-b", shelf(shelfB, "B", at: 2))
        // B writes between A's read and A's write.
        place.beforeWrite = { _ = try await deviceB.sync(place, at: 5) }

        let outcome = try await deviceA.sync(place, at: 6)

        guard case .synced = outcome else { Issue.record("not synced: \(outcome)"); return }
        #expect(place.writes == 2)
        #expect(Set(try place.document().library.collections.map(\.id)) == [shelfA, shelfB])
        #expect(Set(deviceA.library.shelves.collections.map(\.id)) == [shelfA, shelfB])
    }

    @Test func aDocumentThatChangesUnderEveryAttemptIsLeftAlone() async throws {
        let place = MemoryPlace()
        let empty = try LibraryDocumentCoder.encode(
            LibraryExport.document(LibrarySnapshot(), appVersion: "1.0", writtenAt: moment(0))
        )
        place.put(LibrarySync.fileName, empty)
        @Sendable func rewrite() async throws {
            place.put(LibrarySync.fileName, empty)
            place.beforeWrite = rewrite
        }
        place.beforeWrite = rewrite

        #expect(try await SyncDevice("device-a").sync(place, at: 1) == .busy)
        #expect(place.writes == 0)
    }

    @Test func eachRecordNamesTheDeviceAndTheMomentOfItsLastChange() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a", shelf(shelfA, "A", at: 1))
        deviceA.read(book, page: 3, at: 2)
        let deviceB = SyncDevice("device-b")
        deviceB.read(other, page: 9, at: 4)

        try await deviceA.sync(place, at: 10)
        try await deviceB.sync(place, at: 11)

        let written = try place.document().library
        #expect(written.collections.first?.changedBy == "device-a")
        #expect(written.collections.first?.changedAt == moment(1))
        let byIdentity = Dictionary(
            written.progress.map { ($0.identity.contentDigest ?? "", $0.changedBy) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(byIdentity == ["d1": "device-a", "d2": "device-b"])
    }

    @Test func aDocumentWrittenBeforeSyncExistedStillReadsAndMerges() async throws {
        let place = MemoryPlace()
        place.put(LibrarySync.fileName, try LibraryDocumentFixture.document(named: "written-by-android.json"))

        let device = SyncDevice("device-a")
        let outcome = try await device.sync(place, at: 1)

        guard case .synced = outcome else { Issue.record("not synced: \(outcome)"); return }
        #expect(device.library.shelves.collections.map(\.name) == ["Image Comics"])
        #expect(try place.document().library.readingLists.map(\.name) == ["Crossover"])
    }

    @Test func aNewerDocumentIsRefusedByNameAndLeftAsItWas() async throws {
        let place = MemoryPlace()
        let newer = Data(#"{"formatVersion": 99}"#.utf8)
        place.put(LibrarySync.fileName, newer)

        let outcome = try await SyncDevice("device-a").sync(place, at: 1)

        #expect(outcome == .refused(.newerThanThisApp(found: 99, understood: LibraryDocument.currentFormatVersion)))
        #expect(place.files[LibrarySync.fileName]?.data == newer)
    }

    // MARK: 3.6, a provider's conflicted copy

    @Test func eachProvidersNameForAConflictedCopyIsRecognised() {
        for name in [
            "StoryArc Library 2.json",
            "StoryArc Library (1).json",
            "StoryArc Library (Reader's conflicted copy 2026-10-08).json",
            "StoryArc Library-PIXEL8.json",
        ] {
            #expect(LibrarySync.isConflictedCopy(name), "\(name)")
        }
        for name in ["StoryArc Library.json", "Other.json", "StoryArc Library.json.bak", "StoryArc Library2.json"] {
            #expect(!LibrarySync.isConflictedCopy(name), "\(name)")
        }
    }

    private func copy(of snapshot: LibrarySnapshot, by device: String) throws -> Data {
        try LibraryDocumentCoder.encode(
            LibraryExport.syncDocument(
                snapshot, appVersion: "1.0", writtenAt: moment(20), device: device, previous: nil
            )
        )
    }

    @Test func aConflictedCopyWithAFurtherPositionIsMergedAndThenDeleted() async throws {
        let place = MemoryPlace()
        let device = SyncDevice("device-a")
        device.read(book, page: 10, at: 1)
        try await device.sync(place, at: 2)
        let further = LibrarySnapshot(progress: [
            ReadingProgress(identity: book, position: .page(index: 50, of: 100), updatedAt: moment(3)),
        ])
        place.put("StoryArc Library 2.json", try copy(of: further, by: "device-b"))

        let outcome = try await device.sync(place, at: 4)

        guard case let .synced(result) = outcome else { Issue.record("not synced"); return }
        #expect(result.copiesMergedNow == ["StoryArc Library 2.json"])
        #expect(device.position(book)?.position == .page(index: 50, of: 100))
        #expect(try place.document().library.progress.first?.position == DocumentPosition(.page(index: 50, of: 100)))
        #expect(place.files["StoryArc Library 2.json"] == nil)
    }

    @Test func aCorruptConflictedCopyIsSkippedAndNamed() async throws {
        let place = MemoryPlace()
        place.put("StoryArc Library (1).json", Data("{ not a library".utf8))

        let outcome = try await SyncDevice("device-a").sync(place, at: 1)

        guard case let .synced(result) = outcome else { Issue.record("not synced"); return }
        #expect(result.skippedCopies == ["StoryArc Library (1).json"])
        #expect(result.copiesMergedNow.isEmpty)
        #expect(place.files["StoryArc Library (1).json"] != nil)
    }

    @Test func aConflictedCopyThatCannotBeDeletedIsNotMergedTwice() async throws {
        let place = MemoryPlace()
        let device = SyncDevice("device-a")
        place.put("StoryArc Library 2.json", try copy(of: shelf(shelfB, "B", at: 1), by: "device-b"))
        place.undeletable.insert("StoryArc Library 2.json")

        guard case let .synced(first) = try await device.sync(place, at: 2),
              case let .synced(second) = try await device.sync(place, at: 3)
        else { Issue.record("not synced"); return }

        #expect(first.copiesMergedNow == ["StoryArc Library 2.json"])
        #expect(second.copiesMergedNow.isEmpty)
        #expect(first.mergedCopies == second.mergedCopies)
    }

    // MARK: 3.7, Kavita keeps what Kavita owns

    private let kavita = LibraryDocumentFixture.fixed("55555555-5555-5555-5555-555555555555")

    private func kavitaLibrary(page: Int = 4) -> LibrarySnapshot {
        let served = PublicationIdentity(serverIdentifier: .init(sourceID: kavita, remoteID: "chapter:9"))
        let kept = PublicationIdentity(normalizedPath: "/kept/chapter-9.cbz")
        return LibrarySnapshot(
            sources: SourceRegistry(sources: [Source(id: kavita, displayName: "Kavita", kind: .kavitaServer)]),
            progress: [
                ReadingProgress(identity: served, position: .page(index: page, of: 20), updatedAt: moment(1)),
                ReadingProgress(identity: kept, position: .page(index: 5, of: 20), updatedAt: moment(1)),
                ReadingProgress(identity: book, position: .page(index: 6, of: 20), updatedAt: moment(1)),
            ],
            kavitaKept: [kept.stableID]
        )
    }

    @Test func aSyncDocumentCarriesNoKavitaPosition() async throws {
        let place = MemoryPlace()
        try await SyncDevice("device-a", kavitaLibrary()).sync(place, at: 2)

        #expect(try place.document().library.progress.map(\.identity) == [DocumentIdentity(book)])
    }

    @Test func aKavitaPositionIsNeitherTakenFromTheDocumentNorStamped() async throws {
        let place = MemoryPlace()
        // A document from before the rule, which still carries a Kavita position further on.
        let old = LibraryExport.document(kavitaLibrary(page: 19), appVersion: "1.0", writtenAt: moment(1))
        place.put(LibrarySync.fileName, try LibraryDocumentCoder.encode(old))
        let device = SyncDevice("device-a", kavitaLibrary())

        try await device.sync(place, at: 2)

        let served = device.library.progress.first { $0.identity.serverIdentifier != nil }
        #expect(served?.position == .page(index: 4, of: 20))
        #expect(served?.syncedPosition == nil)
    }
}
