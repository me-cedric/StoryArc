import Foundation
@testable import StoryArcCore

/// One library as a sync writes it, described once, so both platforms assert the same document.
///
/// `library-sync` task 5.2. Beside this file is `sync-written-by-ios.json`, the document the iOS
/// sync path writes from ``snapshot``; beside Android's `SyncDocumentFixture` is
/// `sync-written-by-android.json`. Each suite pins its own file and merges the other's.
/// Android's `SyncDocumentFixture` builds the identical library.
enum SyncDocumentFixture {

    static let androidDevice = "android-device"
    static let iosDevice = "ios-device"
    static let appVersion = "10.14.0"

    /// 2026-01-01T00:00:00Z, and the moments after it in seconds.
    static func at(_ second: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_767_225_600 + second) }

    static let written = at(1_000)

    static let collectionID = LibraryDocumentFixture.fixed("33333333-3333-3333-3333-333333333333")
    static let listID = LibraryDocumentFixture.fixed("44444444-4444-4444-4444-444444444444")
    static let kavitaID = LibraryDocumentFixture.fixed("55555555-5555-5555-5555-555555555555")
    static let removedID = LibraryDocumentFixture.fixed("66666666-6666-6666-6666-666666666666")

    static let book = PublicationIdentity(contentDigest: "d1")
    static let novel = PublicationIdentity(contentDigest: "d2")

    /// A reflowable position with its first visible element, `reading-progress` O27.
    static let novelPosition = ReadingPosition.reflowable(
        progression: 0.45,
        locator: #"{"href":"OEBPS/ch1.xhtml"}"#,
        firstVisibleElement: ElementLocator(
            href: "OEBPS/ch1.xhtml",
            cssSelector: "body > p:nth-child(18)",
            textBefore: "the end of seventeen. ",
            textAfter: "Paragraph eighteen begins",
            publicationDigest: "d2"
        )
    )
    static let fontSizeField = "reflowable/|values.fontSizePercent"

    /// The library each platform's sync writes.
    static var snapshot: LibrarySnapshot {
        var larger = ShelfSettings()
        larger.values.fontSize = .large
        var settings = AppSettings()
        settings.appearance = .dark
        return LibrarySnapshot(
            sources: SourceRegistry(sources: [Source(id: kavitaID, displayName: "Kavita", kind: .kavitaServer)]),
            shelves: Shelves(
                collections: [
                    PublicationCollection(
                        id: collectionID, name: "Image Comics", members: ["path:/a.cbz"], changedAt: at(100)
                    ),
                ],
                lists: [
                    ReadingList(
                        id: listID, name: "Crossover", entries: ["path:/b.cbz", "path:/a.cbz"], changedAt: at(200)
                    ),
                ]
            ),
            settings: settings,
            themes: ShelfMemory().settingDefault(larger, for: .reflowable),
            progress: [
                ReadingProgress(identity: book, position: .page(index: 12, of: 40), updatedAt: at(600)),
                ReadingProgress(identity: novel, position: novelPosition, updatedAt: at(600)),
                ReadingProgress(
                    identity: PublicationIdentity(serverIdentifier: .init(sourceID: kavitaID, remoteID: "chapter:9")),
                    position: .page(index: 3, of: 20),
                    updatedAt: at(600)
                ),
            ],
            removedShelves: [ShelfTombstone(id: removedID, removedAt: at(300))],
            settingsChangedAt: ["appearance": at(400)],
            themesChangedAt: [fontSizeField: at(500)]
        )
    }

    /// The device that reads the other platform's document: it holds the same shelves from
    /// before, an older setting and an earlier position.
    static var receiver: LibrarySnapshot {
        var settings = AppSettings()
        settings.appearance = .light
        return LibrarySnapshot(
            shelves: Shelves(collections: [
                PublicationCollection(id: collectionID, name: "Comics", members: ["path:/c.cbz"], changedAt: at(50)),
                PublicationCollection(id: removedID, name: "Gone", changedAt: at(50)),
            ]),
            settings: settings,
            progress: [ReadingProgress(identity: book, position: .page(index: 5, of: 40), updatedAt: at(20))],
            settingsChangedAt: ["appearance": at(10)]
        )
    }

    static var iosPath: URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "sync-written-by-ios.json")
    }

    static func writtenByIOS() throws -> Data { try Data(contentsOf: iosPath) }

    /// Android's document, found by walking up from this file to the repository root.
    static func writtenByAndroid() throws -> Data {
        let path = "apps/android/core/model/src/test/kotlin/app/storyarc/core/model/sync-written-by-android.json"
        var directory = URL(filePath: #filePath)
        while directory.pathComponents.count > 1 {
            directory.deleteLastPathComponent()
            let candidate = directory.appending(path: path)
            if FileManager.default.fileExists(atPath: candidate.path()) { return try Data(contentsOf: candidate) }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
