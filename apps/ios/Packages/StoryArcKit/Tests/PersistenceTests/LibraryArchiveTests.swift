import Foundation
import Testing

import StoryArcCore
@testable import Persistence

/// The seven stores an export reads, written and read back as one.
///
/// `LibraryExport` and `LibraryImport` are asserted without a disk in `StoryArcCoreTests`;
/// this is the half that says the right store holds each part. Android's
/// `LibraryArchiveTest` asserts the same round trip against its own seven.
@Suite("A library archive reads and writes every store the export carries")
struct LibraryArchiveTests {

    private func archive() throws -> (LibraryArchive, UserDefaults) {
        // A suite of its own per test, so one test's library is not another's.
        let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)")
            ?? .standard
        return (LibraryArchive(defaults: defaults, progress: try ProgressStore.inMemory()), defaults)
    }

    private var library: LibrarySnapshot {
        LibrarySnapshot(
            sources: SourceRegistry(sources: [
                Source(displayName: "Comics NAS", kind: .networkShare, locator: "smb://nas/comics"),
            ]),
            certificatePins: ["nas.local": ["AB:CD"]],
            shelves: Shelves(
                collections: [
                    PublicationCollection(
                        name: "Image Comics",
                        members: ["path:/a.cbz"],
                        coverMemberID: "path:/a.cbz"
                    ),
                ],
                lists: [ReadingList(name: "Crossover", entries: ["path:/a.cbz"])]
            ),
            settings: AppSettings(appearance: .oledDark, language: "de"),
            themes: ShelfMemory().settingDefault(
                ShelfSettings(theme: ReadingTheme(preset: .calm)),
                for: .reflowable
            ),
            progress: [
                ReadingProgress(
                    identity: PublicationIdentity(contentDigest: "d1"),
                    position: .page(index: 3, of: 20),
                    updatedAt: Date(timeIntervalSince1970: 1_767_100_000)
                ),
            ]
        )
    }

    @Test("Every store an export carries survives being written and read back")
    func roundTrip() async throws {
        let (archive, _) = try archive()
        var written = library
        written.pinnedShelves = PinnedShelves([
            .collection(written.shelves.collections[0].id),
        ])

        try await archive.apply(written)
        let read = try await archive.snapshot()

        #expect(read.sources.sources.map(\.displayName) == ["Comics NAS"])
        #expect(read.certificatePins == ["nas.local": ["AB:CD"]])
        #expect(read.shelves.collections.first?.coverMemberID == "path:/a.cbz")
        #expect(read.shelves.lists.first?.entries == ["path:/a.cbz"])
        #expect(read.pinnedShelves.tokens == written.pinnedShelves.tokens)
        #expect(read.settings == written.settings)
        #expect(read.themes.default(for: .reflowable).theme.preset == .calm)
        #expect(read.progress.first?.position == .page(index: 3, of: 20))
    }

    @Test("A library with nothing in it reads back as a library with nothing in it")
    func emptyArchive() async throws {
        let (archive, _) = try archive()

        let read = try await archive.snapshot()

        #expect(read.sources.sources.isEmpty)
        #expect(read.progress.isEmpty)
        #expect(read.pinnedShelves.isEmpty)
    }

    @Test("A document written from the archive carries no secret out of the source store")
    func noSecretLeavesTheStores() async throws {
        let (archive, defaults) = try archive()
        SourceStore(defaults: defaults).save(
            SourceRegistry(sources: [
                Source(
                    displayName: "NAS",
                    kind: .networkShare,
                    credentialReference: "keychain:nas",
                    locator: "smb://reader:hunter2@nas.local/comics"
                ),
            ])
        )

        let document = LibraryExport.document(
            try await archive.snapshot(),
            appVersion: "10.14.0",
            writtenAt: Date(timeIntervalSince1970: 0)
        )
        let bytes = String(
            bytes: try LibraryDocumentCoder.encode(document),
            encoding: .utf8
        ) ?? ""

        #expect(!bytes.contains("hunter2"))
        #expect(!bytes.contains("keychain:"))
        #expect(bytes.contains("smb://reader@nas.local/comics"))
    }

    @Test("An imported finished publication stays finished after the write")
    func finishedSurvivesTheWrite() async throws {
        let (archive, _) = try archive()
        var finished = library
        finished.progress = [
            ReadingProgress(
                identity: PublicationIdentity(contentDigest: "d1"),
                position: .page(index: 19, of: 20),
                isFinished: true,
                finishedAt: Date(timeIntervalSince1970: 1_767_100_000),
                updatedAt: Date(timeIntervalSince1970: 1_767_100_000)
            ),
        ]

        try await archive.apply(finished)

        // `ProgressStore.save` is deliberately not allowed to set the flag, so an import that
        // only called it would quietly land every finished publication as unfinished.
        #expect(try await archive.snapshot().progress.first?.isFinished == true)
    }

    // MARK: All or nothing

    /// A progress store that fails on its `failingSave`th save, counting from one.
    private actor FailingLedger: ProgressLedger {
        struct Refused: Error {}

        private let inner: ProgressStore
        private let failingSave: Int
        private var saves = 0

        init(_ inner: ProgressStore, failingSave: Int) {
            self.inner = inner
            self.failingSave = failingSave
        }

        func recent(limit: Int) async throws -> [ReadingProgress] {
            try await inner.recent(limit: limit)
        }

        func save(_ progress: ReadingProgress) async throws {
            saves += 1
            if saves == failingSave { throw Refused() }
            try await inner.save(progress)
        }

        func mark(_ identity: PublicationIdentity, finished: Bool, at: Date) async throws {
            try await inner.mark(identity, finished: finished, at: at)
        }

        func forget(_ identity: PublicationIdentity) async throws {
            try await inner.forget(identity)
        }
    }

    private func record(
        _ digest: String,
        page: Int,
        finished: Bool = false,
        at seconds: TimeInterval = 1_767_100_000
    ) -> ReadingProgress {
        ReadingProgress(
            identity: PublicationIdentity(contentDigest: digest),
            position: .page(index: page, of: 20),
            isFinished: finished,
            finishedAt: finished ? Date(timeIntervalSince1970: seconds) : nil,
            updatedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test("A write that fails part-way leaves the device exactly as it was")
    func aFailedImportChangesNothing() async throws {
        let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)") ?? .standard
        let store = try ProgressStore.inMemory()

        // The device before: one source, one position that is not finished.
        let device = LibraryArchive(defaults: defaults, progress: store)
        var held = LibrarySnapshot()
        held.sources = SourceRegistry(sources: [
            Source(displayName: "Old NAS", kind: .networkShare, locator: "smb://old/comics"),
        ])
        held.settings = AppSettings(appearance: .oledDark, language: "de")
        held.progress = [record("d1", page: 3)]
        try await device.apply(held)
        let before = try await device.snapshot()

        // The import: everything else changes, d1 moves on and is finished, d2 and d3 are new,
        // and the third save is refused. Two saves have landed when it throws.
        var incoming = library
        incoming.progress = [
            record("d1", page: 19, finished: true, at: 1_767_200_000),
            record("d2", page: 4),
            record("d3", page: 5),
        ]
        let failing = LibraryArchive(
            defaults: defaults,
            progress: FailingLedger(store, failingSave: 3)
        )

        await #expect(throws: FailingLedger.Refused.self) {
            try await failing.apply(incoming)
        }

        let after = try await device.snapshot()
        #expect(after == before)
        #expect(after.progress.first { $0.identity.contentDigest == "d1" }?.isFinished == false)
        #expect(after.progress.count == 1)
    }

    // MARK: Covers

    /// A cover store in memory, which can be told to refuse one key.
    private final class MemoryCovers: ChosenCoverStore, @unchecked Sendable {
        private let lock = NSLock()
        private var images: [String: Data]
        private var asked: [String] = []
        let refusing: String?

        init(_ images: [String: Data] = [:], refusing: String? = nil) {
            self.images = images
            self.refusing = refusing
        }

        var held: [String: Data] { lock.withLock { images } }
        var candidatesAsked: [String] { lock.withLock { asked } }

        func chosen(including candidates: [String]) -> [ChosenCover] {
            lock.withLock {
                asked = candidates
                return images.sorted { $0.key < $1.key }.map { ChosenCover(key: $0.key, image: $0.value) }
            }
        }

        func image(forKey key: String) -> Data? { lock.withLock { images[key] } }

        func store(_ image: Data, forKey key: String) -> Bool {
            lock.withLock {
                if key == refusing { return false }
                images[key] = image
                return true
            }
        }

        func remove(forKey key: String) { lock.withLock { images[key] = nil } }
    }

    private func coverArchive(
        covers: MemoryCovers,
        progress: any ProgressLedger
    ) throws -> LibraryArchive {
        let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)") ?? .standard
        return LibraryArchive(defaults: defaults, progress: progress, covers: covers)
    }

    @Test("The archive reads the chosen covers, and offers the store the keys it can try")
    func theArchiveReadsCovers() async throws {
        let covers = MemoryCovers(["sha:d1": Data([1])])
        let archive = try coverArchive(covers: covers, progress: try ProgressStore.inMemory())
        var written = library
        written.covers = [ChosenCover(key: "sha:d1", image: Data([1]))]
        try await archive.apply(written)

        let read = try await archive.snapshot()

        #expect(read.covers == [ChosenCover(key: "sha:d1", image: Data([1]))])
        // A cover chosen before the store filed keys is found by a key the library implies.
        #expect(covers.candidatesAsked.contains("sha:d1"))
        #expect(covers.candidatesAsked.contains("path:/a.cbz"))
    }

    @Test("A failed import puts the covers back: a replaced one returns and a new one goes")
    func aFailedImportRestoresCovers() async throws {
        let covers = MemoryCovers(["sha:held": Data([1])])
        let store = try ProgressStore.inMemory()
        let device = try coverArchive(covers: covers, progress: store)
        let before = try await device.snapshot()

        var incoming = library
        incoming.covers = [
            ChosenCover(key: "sha:held", image: Data([2])),
            ChosenCover(key: "sha:new", image: Data([3])),
        ]
        incoming.progress = [record("d1", page: 1), record("d2", page: 2)]
        let failing = try coverArchive(covers: covers, progress: FailingLedger(store, failingSave: 2))

        await #expect(throws: FailingLedger.Refused.self) {
            try await failing.apply(incoming)
        }

        #expect(covers.held == ["sha:held": Data([1])])
        #expect(try await device.snapshot() == before)
    }

    @Test("A cover that cannot be written fails the import and undoes the covers before it")
    func aCoverThatWillNotWriteFailsTheImport() async throws {
        let covers = MemoryCovers(["sha:held": Data([1])], refusing: "sha:b")
        let archive = try coverArchive(covers: covers, progress: try ProgressStore.inMemory())
        let before = try await archive.snapshot()

        var incoming = library
        incoming.covers = [
            ChosenCover(key: "sha:a", image: Data([2])),
            ChosenCover(key: "sha:b", image: Data([3])),
        ]

        await #expect(throws: LibraryArchive.CoverNotWritten(key: "sha:b")) {
            try await archive.apply(incoming)
        }

        #expect(covers.held == ["sha:held": Data([1])])
        #expect(try await archive.snapshot() == before)
    }
}
