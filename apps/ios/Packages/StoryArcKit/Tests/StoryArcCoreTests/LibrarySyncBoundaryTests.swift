import Foundation
import Testing
@testable import StoryArcCore

/// `library-sync` task 5.2: a document one platform's sync path writes merges on the other.
///
/// This suite pins `sync-written-by-ios.json` and merges `sync-written-by-android.json`.
/// Android's `LibrarySyncBoundaryTest` does the reverse.
struct LibrarySyncBoundaryTests {

    private typealias Fixture = SyncDocumentFixture

    private func writtenHere() async throws -> Data {
        let place = MemoryPlace()
        _ = try await LibrarySync(place: place, device: Fixture.iosDevice, appVersion: Fixture.appVersion)
            .sync(Fixture.snapshot, at: Fixture.written)
        return place.files[LibrarySync.fileName]?.data ?? Data()
    }

    @Test func thisPlatformsSyncPathStillWritesTheCommittedDocument() async throws {
        #expect(try await writtenHere() == Fixture.writtenByIOS())
    }

    @Test func aDocumentAndroidWroteNamesTheDeviceAndTheMomentOfEachRecord() throws {
        let library = try LibraryDocumentCoder.decode(Fixture.writtenByAndroid()).library

        #expect(library.collections.first?.changedAt == Fixture.at(100))
        #expect(library.collections.first?.changedBy == Fixture.androidDevice)
        #expect(library.readingLists.first?.changedAt == Fixture.at(200))
        #expect(library.readingLists.first?.changedBy == Fixture.androidDevice)
        #expect(library.removedShelves?.first?.removedAt == Fixture.at(300))
        #expect(library.removedShelves?.first?.removedBy == Fixture.androidDevice)
        #expect(
            library.settings.changed?["appearance"] == DocumentStamp(at: Fixture.at(400), by: Fixture.androidDevice)
        )
        #expect(
            library.readingThemes.changed?[Fixture.fontSizeField]
                == DocumentStamp(at: Fixture.at(500), by: Fixture.androidDevice)
        )
        // The Kavita position stayed with Kavita.
        #expect(library.progress.map(\.changedBy) == [Fixture.androidDevice])
    }

    @Test func aDocumentAndroidWroteMergesHere() async throws {
        let place = MemoryPlace()
        place.put(LibrarySync.fileName, try Fixture.writtenByAndroid())
        let device = SyncDevice(Fixture.iosDevice, Fixture.receiver)

        let outcome = try await device.sync(place, at: 2_000)

        guard case .synced = outcome else { Issue.record("not synced: \(outcome)"); return }
        let library = device.library
        #expect(device.position(Fixture.book)?.position == .page(index: 12, of: 40))
        #expect(library.shelves.collections.map(\.id) == [Fixture.collectionID])
        #expect(library.shelves.collections.first?.name == "Image Comics")
        #expect(library.shelves.collections.first?.members == ["path:/a.cbz", "path:/c.cbz"])
        #expect(library.shelves.lists.first?.entries == ["path:/b.cbz", "path:/a.cbz"])
        #expect(library.removedShelves.map(\.id) == [Fixture.removedID])
        #expect(library.settings.appearance == .dark)
        #expect(library.themes.default(for: .reflowable).values.fontSize == .large)
        #expect(device.conflicts.isEmpty)

        // What this device writes back still names the device that made each change.
        let written = try place.document().library
        #expect(written.collections.first?.changedBy == Fixture.androidDevice)
        #expect(written.removedShelves?.first?.removedBy == Fixture.androidDevice)
        #expect(written.settings.changed?["appearance"]?.by == Fixture.androidDevice)
    }
}
