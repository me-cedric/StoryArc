import Foundation

@testable import StoryArcCore

/// One library, described once, so both platforms assert the same document.
///
/// `packages/test-fixtures/library/` holds what each platform's encoder writes from this
/// snapshot. Each suite pins its own file and reads the other's, which is what makes task
/// 1.2's claim — "a test writes on one platform's encoder and reads on the other's decoder" —
/// something a gate can fail on rather than something a handoff asserts.
///
/// Android's `LibraryDocumentFixture` builds the identical library.
enum LibraryDocumentFixture {

    /// A UUID that reads the same in both suites' fixtures.
    ///
    /// A zero UUID rather than a force unwrap on a string this file wrote itself: the
    /// fallback is unreachable, and `swiftlint` is right that a reader cannot tell that from
    /// a force unwrap that is not.
    static func fixed(_ text: String) -> UUID { UUID(uuidString: text) ?? UUID() }

    static let writtenAt = Date(timeIntervalSince1970: 1_767_225_845)

    static let appVersion = "10.14.0"

    static let networkShareID = fixed("11111111-1111-1111-1111-111111111111")
    static let folderID = fixed("22222222-2222-2222-2222-222222222222")
    static let collectionID = fixed("33333333-3333-3333-3333-333333333333")
    static let listID = fixed("44444444-4444-4444-4444-444444444444")
    static let kavitaID = fixed("55555555-5555-5555-5555-555555555555")

    /// The secrets the export must never carry. See `LibraryExportSecrecyTests`.
    static let password = "hunter2correcthorse"
    static let token = "eyJhbGciOiJIUzI1NiJ9.aGVsbG8.sig"
    static let apiKey = "ak-9f3c2b1a7e5d4c6b8a0f2e1d3c4b5a69"

    /// Where the committed documents live, found by walking up from this file the way every
    /// other corpus-reading suite in this package does.
    static var corpus: URL {
        var directory = URL(filePath: #filePath)
        while directory.pathComponents.count > 1 {
            directory.deleteLastPathComponent()
            let corpus = directory.appending(path: "packages/test-fixtures/library")
            if FileManager.default.fileExists(atPath: corpus.path()) { return corpus }
        }
        fatalError("fixture corpus not found — expected packages/test-fixtures above \(#filePath)")
    }

    static func document(named name: String) throws -> Data {
        try Data(contentsOf: corpus.appending(path: name))
    }

    /// The cover the reader chose for the first publication: a one-pixel PNG, the same bytes
    /// on both platforms, filed under the key the cover store uses for a digest.
    static let coverKey = "sha:d1"
    static let coverImage = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==") ?? Data()

    /// The library both platforms export.
    static var snapshot: LibrarySnapshot {
        LibrarySnapshot(
            sources: SourceRegistry(sources: [
                Source(
                    id: networkShareID,
                    displayName: "Comics NAS",
                    kind: .networkShare,
                    lastSuccessfulSync: Date(timeIntervalSince1970: 1_767_139_445),
                    // The password is in the address, which is where an SMB mount puts one.
                    credentialReference: "keychain:\(networkShareID.uuidString)",
                    locator: "smb://reader:\(password)@nas.local/comics"
                ),
                Source(
                    id: folderID,
                    displayName: "Shelf",
                    kind: .localFolder,
                    locator: "/Books/Shelf"
                ),
                Source(
                    id: kavitaID,
                    displayName: "Kavita",
                    kind: .kavitaServer,
                    credentialReference: "keychain:\(kavitaID.uuidString)",
                    locator: "https://kavita.example/api?apikey=\(apiKey)&library=3"
                ),
            ]),
            certificatePins: ["nas.local": ["AB:CD:EF:01"]],
            shelves: Shelves(
                collections: [
                    PublicationCollection(
                        id: collectionID,
                        name: "Image Comics",
                        members: ["path:/a.cbz", "path:/b.cbz"],
                        coverMemberID: "path:/b.cbz"
                    ),
                ],
                lists: [
                    ReadingList(
                        id: listID,
                        name: "Crossover",
                        entries: ["path:/b.cbz", "path:/a.cbz"]
                    ),
                ]
            ),
            pinnedShelves: PinnedShelves([.collection(collectionID), .list(listID)]),
            settings: AppSettings(
                appearance: .oledDark,
                language: "fr",
                turnPagesByTappingTheEdges: false,
                linkReadingThemeToAppearance: true,
                lightReadingTheme: .calm,
                darkReadingTheme: .focus,
                downloadOverWifiOnly: true,
                maximumDownloadBytes: 4_294_967_296,
                removeDownloadsAfterFinishing: true
            ),
            themes: themes,
            progress: [
                ReadingProgress(
                    identity: PublicationIdentity(
                        contentDigest: "d1",
                        normalizedPath: "/a.cbz"
                    ),
                    position: .page(index: 12, of: 40),
                    updatedAt: Date(timeIntervalSince1970: 1_767_100_000)
                ),
                ReadingProgress(
                    identity: PublicationIdentity(contentDigest: "d2"),
                    position: .reflowable(progression: 0.375, locator: "{\"href\":\"ch3\"}"),
                    isFinished: true,
                    finishedAt: Date(timeIntervalSince1970: 1_767_110_000),
                    updatedAt: Date(timeIntervalSince1970: 1_767_110_000),
                    // Present on this device, and deliberately absent from the document.
                    syncedPosition: .reflowable(progression: 0.1, locator: "{}")
                ),
                ReadingProgress(
                    identity: PublicationIdentity(
                        serverIdentifier: .init(sourceID: kavitaID, remoteID: "901")
                    ),
                    position: .listening(part: 2, partCount: 9, offset: 61.5, of: 600),
                    updatedAt: Date(timeIntervalSince1970: 1_767_120_000)
                ),
            ],
            covers: [ChosenCover(key: coverKey, image: coverImage)]
        )
    }

    private static var themes: ShelfMemory {
        let reflowableDefault = ShelfSettings(
            theme: ReadingTheme(preset: .quiet, deviations: [.fontSize, .lineSpacing]),
            values: ThemeValues(typeface: .literata, fontSize: .large, lineHeight: 1.8),
            transition: .fastFade
        )
        let bone = ShelfSettings(
            transition: .scroll(.vertical),
            adjustments: ImageAdjustments(brightness: 0.2, isGreyscale: true),
            offsetsSpreads: true,
            fit: .width
        )
        var memory = ShelfMemory()
            .settingDefault(reflowableDefault, for: .reflowable)
            .remembering(bone, for: .fixedLayout, shelf: "Bone")
        memory.customPalette = ReaderPalette(
            name: "Midnight",
            background: "#101014",
            foreground: "#E8E8F0"
        )
        return memory
    }
}
