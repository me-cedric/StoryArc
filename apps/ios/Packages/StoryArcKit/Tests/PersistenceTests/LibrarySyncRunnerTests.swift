import Foundation
import Synchronization
import Testing

import StoryArcCore
@testable import Persistence

/// A place in memory that counts what it is asked, and that can stop answering.
private final class CountingPlace: SyncPlace {
    private let files = Mutex<[String: SyncFile]>([:])
    private let counts = Mutex((calls: 0, writes: 0, version: 0, closes: 0))
    private let away = Mutex(false)
    private let hook = Mutex<(@Sendable () async -> Void)?>(nil)

    var calls: Int { counts.withLock { $0.calls } }
    var writes: Int { counts.withLock { $0.writes } }
    var closes: Int { counts.withLock { $0.closes } }
    func setAway(_ isAway: Bool) { away.withLock { $0 = isAway } }

    /// Runs `action` once, between the next sync's read and its write.
    func beforeNextWrite(_ action: @escaping @Sendable () async -> Void) { hook.withLock { $0 = action } }

    private func answer() throws {
        counts.withLock { $0.calls += 1 }
        if away.withLock({ $0 }) { throw URLError(.cannotConnectToHost) }
    }

    func names() async throws -> [String] {
        try answer()
        return files.withLock { Array($0.keys) }
    }

    func read(_ name: String) async throws -> SyncFile? {
        try answer()
        return files.withLock { $0[name] }
    }

    func write(_ name: String, data: Data, replacing: String?) async throws -> Bool {
        try answer()
        let action = hook.withLock { held in
            defer { held = nil }
            return held
        }
        await action?()
        return files.withLock { held in
            guard held[name]?.version == replacing else { return false }
            let version = counts.withLock { $0.writes += 1; $0.version += 1; return "v\($0.version)" }
            held[name] = SyncFile(data: data, version: version)
            return true
        }
    }

    func delete(_ name: String) async throws -> Bool {
        try answer()
        return files.withLock { $0.removeValue(forKey: name) != nil }
    }

    func close() async { counts.withLock { $0.closes += 1 } }

    func positions() throws -> [String] {
        let data = try #require(files.withLock { $0[LibrarySync.fileName]?.data })
        return try LibraryDocumentCoder.decode(data).library.progress.compactMap(\.identity.contentDigest)
    }
}

/// What the runner's closures count, kept apart from the device so they capture no device.
@MainActor
private final class Counters {
    var now = Date(timeIntervalSince1970: 1_767_225_600)
    var placesBuilt = 0
    var reloads = 0
    var conflicts: [[ProgressPull.Conflict]] = []
}

/// One device: real stores in a suite of its own, a clock the test moves, and a runner.
@MainActor
private final class SyncDevice {
    let counters = Counters()
    let place: CountingPlace
    let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)") ?? .standard
    let progress: ProgressStore
    let runner: LibrarySyncRunner

    var now: Date {
        get { counters.now }
        set { counters.now = newValue }
    }

    var placesBuilt: Int { counters.placesBuilt }
    var reloads: Int { counters.reloads }

    init(place: CountingPlace = CountingPlace()) throws {
        self.place = place
        progress = try ProgressStore.inMemory()
        let transfer = LibraryTransfer(
            archive: LibraryArchive(defaults: defaults, progress: progress),
            secrets: MemorySecrets()
        )
        let state = LibrarySyncState(defaults: defaults)
        let place = place
        let counters = counters
        runner = LibrarySyncRunner(
            places: SyncPlaceStore(defaults: defaults),
            placeFor: { _ in
                counters.placesBuilt += 1
                return place
            },
            sync: { try await transfer.sync(with: $0, state: state, appVersion: "1.0") },
            now: { counters.now }
        )
        runner.onSynced = { counters.reloads += 1 }
        runner.onConflicts = { counters.conflicts.append($0) }
    }

    var conflicts: [[ProgressPull.Conflict]] { counters.conflicts }

    /// A position on page `index` of the book the tests read, or of the book `digest`.
    func page(_ index: Int, of digest: String = "d1") -> ReadingProgress {
        ReadingProgress(
            identity: PublicationIdentity(contentDigest: digest), position: .page(index: index, of: 100), updatedAt: now
        )
    }

    /// Reads `digest` to page `index`, as the reader's save writes it: the synchronised
    /// position stays the one the last sync left.
    func read(_ digest: String, to index: Int) async throws {
        let identity = PublicationIdentity(contentDigest: digest)
        var record = try await progress.progress(for: identity) ?? page(index, of: digest)
        record.position = .page(index: index, of: 100)
        record.updatedAt = now
        try await progress.save(record)
    }

    var shelves: ShelvesStore { ShelvesStore(defaults: defaults) }
}

/// `library-sync` tasks 2.1, 2.4, 4.1 and 4.2: when a sync runs, through the real stores and
/// the real engine. Android's `LibrarySyncRunnerTest` makes the same claims.
@MainActor
struct LibrarySyncRunnerTests {

    @Test func syncIsOffUntilAPlaceIsChosenAndOffReadsAndWritesNothing() async throws {
        let device = try SyncDevice()
        #expect(device.runner.status == .off)
        for trigger in LibrarySyncRunner.Trigger.allCases { #expect(await !device.runner.run(trigger)) }
        #expect(await !device.runner.leftPublication(ownedByKavita: false))

        #expect(device.placesBuilt == 0)
        #expect(device.place.calls == 0)
        #expect(device.runner.status == .off)
    }

    @Test func theForegroundRunsOneSyncAndSkipsASecondOneInside30Seconds() async throws {
        let device = try SyncDevice()
        device.runner.chooseShare(UUID())

        #expect(await device.runner.run(.foreground))
        #expect(device.place.writes == 1)
        #expect(device.reloads == 1)
        device.now += 10
        #expect(await !device.runner.run(.foreground))
        #expect(device.place.writes == 1)

        device.now += LibrarySyncRunner.throttle
        #expect(await device.runner.run(.foreground))
        #expect(device.placesBuilt == 2)
    }

    @Test func aPlaceThatDoesNotAnswerLeavesTheLibraryWorkingAndGreyAndALaterSyncRecovers() async throws {
        let device = try SyncDevice()
        device.runner.chooseShare(UUID())
        device.shelves.save(Shelves().adding(PublicationCollection(id: UUID(), name: "Kept")))
        device.place.setAway(true)

        #expect(await device.runner.run(.foreground))
        #expect(device.runner.status == .unreachable)
        #expect(device.shelves.shelves().collections.map(\.name) == ["Kept"])
        // A place that failed is still ended, so a share's session is not left open.
        #expect(device.place.closes == 1)

        // The failure queued a retry, so the next trigger runs inside the throttle.
        device.place.setAway(false)
        device.now += 1
        #expect(await device.runner.run(.foreground))
        #expect(device.runner.status == .synced(device.now))
        #expect(device.place.closes == 2)
    }

    @Test func leavingAPublicationWritesItsPositionAtOnceAndAKavitaPublicationWritesNothing() async throws {
        let device = try SyncDevice()
        device.runner.chooseShare(UUID())
        try await device.progress.save(device.page(40))

        #expect(await !device.runner.leftPublication(ownedByKavita: true))
        #expect(device.place.calls == 0)

        #expect(await device.runner.leftPublication(ownedByKavita: false))
        #expect(device.place.writes == 1)
        #expect(try device.place.positions() == ["d1"])
    }

    @Test func theBackgroundRefreshIsAskedForOnlyWhileSyncIsOn() throws {
        let device = try SyncDevice()
        var submitted: [Date] = []
        var cancels = 0
        device.runner.scheduleBackgroundRefresh(submit: { submitted.append($0) }, cancel: { cancels += 1 })
        #expect(submitted.isEmpty)
        #expect(cancels == 1)

        device.runner.chooseShare(UUID())
        device.runner.scheduleBackgroundRefresh(submit: { submitted.append($0) }, cancel: { cancels += 1 })
        #expect(submitted == [device.now.addingTimeInterval(15 * 60)])
        #expect(cancels == 1)
    }

    /// Task 5.6: a refused request is not swallowed. The runner says so until a request is taken.
    @Test func aRefusedBackgroundRefreshIsShownAndATakenOneClearsIt() throws {
        let device = try SyncDevice()
        device.runner.chooseShare(UUID())
        #expect(!device.runner.isBackgroundRefused)

        device.runner.scheduleBackgroundRefresh(submit: { _ in throw URLError(.cancelled) }, cancel: {})
        #expect(device.runner.isBackgroundRefused)

        device.runner.scheduleBackgroundRefresh(submit: { _ in }, cancel: {})
        #expect(!device.runner.isBackgroundRefused)
    }

    @Test func theBackgroundRefreshRunsTheSameSyncAndIsNotThrottled() async throws {
        let device = try SyncDevice()
        device.runner.chooseShare(UUID())
        #expect(await device.runner.run(.foreground))
        device.now += 1
        #expect(await device.runner.run(.background))
        #expect(device.place.writes == 2)
    }

    @Test func aTriggerDuringASyncRunsTheSyncOnceMoreWhenItEnds() async throws {
        let device = try SyncDevice()
        device.runner.chooseShare(UUID())
        let (inside, entered) = AsyncStream<Void>.makeStream()
        let (release, released) = AsyncStream<Void>.makeStream()
        device.place.beforeNextWrite {
            entered.yield()
            for await _ in release { break }
        }

        let first = Task { await device.runner.run(.foreground) }
        for await _ in inside { break }
        // The position is saved while the first sync waits on the place.
        try await device.progress.save(device.page(7))
        #expect(await !device.runner.leftPublication(ownedByKavita: false))
        released.yield()
        #expect(await first.value)

        #expect(device.place.writes == 2)
        #expect(try device.place.positions() == ["d1"])
    }

    /// `library-sync` task 5.4: a sync that found positions both devices had moved hands them
    /// to the notice, and a sync that found none hands nothing.
    @Test func positionsBothDevicesMovedReachTheNoticeAndNoneReachNothing() async throws {
        let place = CountingPlace()
        let first = try SyncDevice(place: place)
        let second = try SyncDevice(place: place)
        first.runner.chooseShare(UUID())
        second.runner.chooseShare(UUID())
        for digest in ["d1", "d2"] { try await first.read(digest, to: 20) }
        #expect(await first.runner.run(.chosen))
        #expect(await second.runner.run(.chosen))
        #expect(first.conflicts.isEmpty)
        #expect(second.conflicts.isEmpty)

        try await first.read("d1", to: 40)
        #expect(await first.runner.run(.leftPublication))
        try await second.read("d1", to: 30)
        #expect(await second.runner.run(.leftPublication))
        let one = try #require(second.conflicts.last)
        #expect(one.map(\.resolved.position) == [.page(index: 40, of: 100)])
        #expect(one.map(\.discarded) == [.page(index: 30, of: 100)])

        for digest in ["d1", "d2"] { try await first.read(digest, to: 60) }
        #expect(await first.runner.run(.leftPublication))
        for digest in ["d1", "d2"] { try await second.read(digest, to: 50) }
        #expect(await second.runner.run(.leftPublication))
        #expect(second.conflicts.count == 2)
        #expect(second.conflicts.last?.count == 2)
        #expect(first.conflicts.isEmpty)
    }
}
