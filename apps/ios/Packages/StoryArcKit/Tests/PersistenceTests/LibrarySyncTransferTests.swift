import Foundation
import Synchronization
import Testing

import StoryArcCore
@testable import Persistence

/// A sync place in memory, with a version that moves on every write.
private final class Place: SyncPlace {
    private let files = Mutex<[String: SyncFile]>([:])
    private let version = Mutex(0)
    private let hook = Mutex<(@Sendable () async throws -> Void)?>(nil)

    /// Runs `action` once, between the next sync's read and its write.
    func beforeNextWrite(_ action: @escaping @Sendable () async throws -> Void) {
        hook.withLock { $0 = action }
    }

    func names() async throws -> [String] { files.withLock { Array($0.keys) } }

    func read(_ name: String) async throws -> SyncFile? { files.withLock { $0[name] } }

    func write(_ name: String, data: Data, replacing: String?) async throws -> Bool {
        let action = hook.withLock { held in
            defer { held = nil }
            return held
        }
        try await action?()
        let next = version.withLock { $0 += 1; return "v\($0)" }
        return files.withLock { held in
            guard held[name]?.version == replacing else { return false }
            held[name] = SyncFile(data: data, version: next)
            return true
        }
    }

    func delete(_ name: String) async throws -> Bool {
        files.withLock { $0.removeValue(forKey: name) != nil }
    }
}

/// A clock a test moves.
private final class Clock: Sendable {
    private let held = Mutex(Date(timeIntervalSince1970: 1_767_225_600))
    var now: Date { held.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { held.withLock { $0 += seconds } }
}

/// One device with real stores in a suite of its own, a clock, and its own sync state.
private struct Device {
    let clock = Clock()
    let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)") ?? .standard
    let progress: ProgressStore
    let transfer: LibraryTransfer

    init() throws {
        progress = try ProgressStore.inMemory()
        let clock = self.clock
        transfer = LibraryTransfer(
            archive: LibraryArchive(defaults: defaults, progress: progress, now: { clock.now }),
            secrets: MemorySecrets()
        )
    }

    var shelves: ShelvesStore { ShelvesStore(defaults: defaults, now: { [clock] in clock.now }) }
    var settings: SettingsStore { SettingsStore(defaults: defaults, now: { [clock] in clock.now }) }

    @discardableResult
    func sync(_ place: Place) async throws -> LibrarySyncOutcome {
        clock.advance(1)
        return try await transfer.sync(
            with: place, state: LibrarySyncState(defaults: defaults), appVersion: "1.0", at: clock.now
        )
    }
}

/// `library-sync` tasks 3.1, 3.4 and 3.5 through the real stores: what a screen saves is
/// stamped, a sync carries it, and the other device's stores hold it after its own sync.
/// Android's `LibrarySyncTransferTest` makes the same claims.
struct LibrarySyncTransferTests {

    private let shelf = (UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003") ?? UUID())

    @Test func aShelfDeletedOnOneDeviceIsGoneFromTheOtherDevicesStore() async throws {
        let place = Place()
        let deviceA = try Device()
        let deviceB = try Device()
        deviceA.shelves.save(Shelves().adding(PublicationCollection(id: shelf, name: "Image")))
        try await deviceA.sync(place)
        try await deviceB.sync(place)
        #expect(deviceB.shelves.shelves().collections.map(\.id) == [shelf])

        deviceA.clock.advance(5)
        deviceA.shelves.save(deviceA.shelves.shelves().deleting(collection: shelf))
        try await deviceA.sync(place)
        try await deviceB.sync(place)
        try await deviceB.sync(place)

        #expect(deviceB.shelves.shelves().collections.isEmpty)
        #expect(deviceB.shelves.removed().map(\.id) == [shelf])
    }

    @Test func aMemberASyncTookFromTheOtherDeviceDoesNotOutrunALaterDeletion() async throws {
        let place = Place()
        let deviceA = try Device()
        let deviceB = try Device()
        deviceA.shelves.save(Shelves().adding(PublicationCollection(id: shelf, name: "Image", members: ["m:1"])))
        try await deviceA.sync(place)
        try await deviceB.sync(place)
        deviceB.clock.advance(5)
        deviceB.shelves.save(deviceB.shelves.shelves().adding(["m:2"], to: shelf))
        try await deviceB.sync(place)
        // A renames the shelf after B's member, and B deletes it after the rename.
        deviceA.clock.advance(11)
        deviceA.shelves.save(deviceA.shelves.shelves().renaming(collection: shelf, to: "Image Comics"))
        deviceB.clock.advance(10)
        deviceB.shelves.save(deviceB.shelves.shelves().deleting(collection: shelf))
        deviceA.clock.advance(5)

        // A takes B's member. That is not a change A made, so the deletion still wins.
        try await deviceA.sync(place)
        try await deviceB.sync(place)
        try await deviceA.sync(place)
        try await deviceB.sync(place)

        #expect(deviceA.shelves.shelves().collections.isEmpty)
        #expect(deviceB.shelves.shelves().collections.isEmpty)
    }

    @Test func aPageTurnedWhileASyncRunsIsNotPutBack() async throws {
        let place = Place()
        let deviceA = try Device()
        let book = PublicationIdentity(contentDigest: "d1")
        let progress = deviceA.progress
        let now = deviceA.clock.now
        @Sendable func page(_ index: Int) -> ReadingProgress {
            ReadingProgress(identity: book, position: .page(index: index, of: 100), updatedAt: now)
        }
        try await progress.save(page(40))
        try await deviceA.sync(place)
        place.beforeNextWrite { try await progress.save(page(41)) }

        try await deviceA.sync(place)

        #expect(try await progress.recent(limit: 10).first?.position == .page(index: 41, of: 100))
    }

    @Test func aSettingChangedOnEachDeviceSurvivesOnBoth() async throws {
        let place = Place()
        let deviceA = try Device()
        let deviceB = try Device()
        var dark = deviceA.settings.settings()
        dark.appearance = .dark
        deviceA.settings.save(dark)
        deviceB.clock.advance(2)
        var french = deviceB.settings.settings()
        french.language = "fr"
        deviceB.settings.save(french)

        try await deviceA.sync(place)
        try await deviceB.sync(place)
        try await deviceA.sync(place)

        for device in [deviceA, deviceB] {
            #expect(device.settings.settings().appearance == .dark)
            #expect(device.settings.settings().language == "fr")
        }
    }

    @Test func aPositionReachesTheOtherDeviceWithItsWatermark() async throws {
        let place = Place()
        let deviceA = try Device()
        let deviceB = try Device()
        let book = PublicationIdentity(contentDigest: "d1")
        try await deviceA.progress.save(
            ReadingProgress(identity: book, position: .page(index: 40, of: 100), updatedAt: deviceA.clock.now)
        )

        try await deviceA.sync(place)
        try await deviceB.sync(place)

        let arrived = try await deviceB.progress.recent(limit: 10)
        #expect(arrived.first?.position == .page(index: 40, of: 100))
        #expect(arrived.first?.syncedPosition == .page(index: 40, of: 100))
    }

    @Test func anInstallKeepsOneDeviceID() {
        let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)") ?? .standard
        let state = LibrarySyncState(defaults: defaults)
        let first = state.deviceID()
        #expect(state.deviceID() == first)
        let other = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)") ?? .standard
        #expect(LibrarySyncState(defaults: other).deviceID() != first)
    }

    @Test func aStoreStampsAChangeAndRecordsADeletion() throws {
        let device = try Device()
        device.shelves.save(Shelves().adding(PublicationCollection(id: shelf, name: "Image")))
        #expect(device.shelves.shelves().collections.first?.changedAt == device.clock.now)

        device.clock.advance(4)
        device.shelves.save(device.shelves.shelves().deleting(collection: shelf))
        #expect(device.shelves.removed().first?.removedAt == device.clock.now)
    }

    @Test func aSettingsStoreStampsTheFieldTheReaderChanged() throws {
        let device = try Device()
        var german = device.settings.settings()
        german.language = "de"
        device.settings.save(german)
        #expect(device.settings.changedAt() == ["language": device.clock.now])
    }

    @Test func aThemeStoreStampsTheFieldTheReaderChanged() throws {
        let device = try Device()
        let reader = ReaderPreferences(defaults: device.defaults, now: { [clock = device.clock] in clock.now })
        let themes = reader.themes()
        var larger = themes.default(for: .reflowable)
        larger.values.fontSize = .large
        reader.save(themes.settingDefault(larger, for: .reflowable))
        #expect(reader.themesChangedAt() == ["reflowable/|values.fontSizePercent": device.clock.now])
    }
}
