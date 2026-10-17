import Formats
import Foundation
import Persistence
import Smb
import StoryArcCore
import Testing

@testable import StoryArc

/// Task 3.13, test first: sync at start and at quit, over a location that answers slowly.
///
/// `desktop-experience`, *Sync when the app runs*: at start the sync never blocks the window;
/// at quit it writes once more if a position changed, within five seconds, and the app quits
/// whatever the result; an unreachable place is grey and the app reads normally.
@MainActor
@Suite("Sync at start and quit")
struct SyncTests {
    /// A place that takes `delay` to answer every sync, or fails.
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func add() { lock.withLock { count += 1 } }
    }

    private struct NoPlace: SyncPlace {
        func names() async throws -> [String] { [] }
        func read(_ name: String) async throws -> SyncFile? { nil }
        func write(_ name: String, data: Data, replacing: String?) async throws -> Bool { true }
        func delete(_ name: String) async throws -> Bool { true }
        func close() async {}
    }

    private struct Unreachable: Error {}

    private func runner(delay: Duration, fails: Bool = false, calls: Calls) -> LibrarySyncRunner {
        let defaults = UserDefaults(suiteName: "app.storyarc.mac.tests.sync.\(UUID().uuidString)") ?? .standard
        let places = SyncPlaceStore(defaults: defaults)
        places.chooseShare(UUID())
        return LibrarySyncRunner(
            places: places,
            placeFor: { _ in NoPlace() },
            sync: { _ in
                calls.add()
                try await Task.sleep(for: delay)
                if fails { throw Unreachable() }
                return .busy
            }
        )
    }

    @Test("At start the sync runs beside the window, which is never kept waiting")
    func startDoesNotBlock() async {
        let calls = Calls()
        let sync = MacSync(runner: runner(delay: .seconds(30), calls: calls), latestChange: { nil })
        let clock = ContinuousClock()
        let started = clock.now
        sync.start {}
        #expect(clock.now - started < .milliseconds(200))
        _ = await Walk.until(.seconds(2)) { calls.value > 0 ? true : nil }
        #expect(calls.value == 1)
        #expect(!sync.hasSettledStart)
    }

    @Test("At start, what the sync brought is reloaded once it lands, and Keep reading may show")
    func startThenReload() async {
        let calls = Calls()
        let sync = MacSync(runner: runner(delay: .milliseconds(50), calls: calls), latestChange: { nil })
        var reloaded = false
        sync.start { reloaded = true }
        _ = await Walk.until(.seconds(3)) { sync.hasSettledStart ? true : nil }
        #expect(reloaded)
    }

    @Test("At quit, a changed position is written once more, and a slow place gives up within five seconds")
    func quitWithSlowPlace() async {
        let calls = Calls()
        let sync = MacSync(runner: runner(delay: .seconds(30), calls: calls), latestChange: { Date() })
        let clock = ContinuousClock()
        let began = clock.now
        let outcome = await sync.atQuit()
        let took = clock.now - began
        #expect(outcome == .gaveUp)
        #expect(took < .seconds(6), "the quit waited \(took)")
        #expect(took >= MacSync.quitDeadline - .milliseconds(100))
        ConformanceLog.note("sync at quit, slow place", "gave up after \(took)")
    }

    @Test("At quit, a quick place is written and the quit goes on")
    func quitWithQuickPlace() async {
        let calls = Calls()
        let sync = MacSync(runner: runner(delay: .milliseconds(20), calls: calls), latestChange: { Date() })
        #expect(await sync.atQuit() == .synced)
        #expect(calls.value == 1)
    }

    @Test("At quit, no position changed since the last sync: nothing is written")
    func quitWithNothingNew() async {
        let calls = Calls()
        let sync = MacSync(
            runner: runner(delay: .milliseconds(20), calls: calls),
            latestChange: { Date(timeIntervalSince1970: 0) }
        )
        sync.start {}
        _ = await Walk.until(.seconds(3)) { sync.hasSettledStart ? true : nil }
        #expect(await sync.atQuit() == .nothingNew)
        #expect(calls.value == 1, "only the start's sync ran")
    }

    @Test("An unreachable place is grey, and the start still settles")
    func unreachable() async {
        let calls = Calls()
        let runner = runner(delay: .milliseconds(20), fails: true, calls: calls)
        let sync = MacSync(runner: runner, latestChange: { nil })
        sync.start {}
        _ = await Walk.until(.seconds(3)) { sync.hasSettledStart ? true : nil }
        #expect(runner.status == .unreachable)
        #expect(sync.hasSettledStart)
    }

    @Test("A real share takes the sync document, through the Mac's own runner wiring",
          .enabled(if: MockServers.isSmbUp, "the SMB mock is not running (pnpm smb --writable)"))
    func realShare() async throws {
        let library = try await Walk.library()
        let defaults = UserDefaults(suiteName: "app.storyarc.mac.tests.sync.\(UUID().uuidString)") ?? .standard
        let places = SyncPlaceStore(defaults: defaults)
        places.chooseShare(UUID())
        let address = SmbAddress(
            host: "127.0.0.1", share: "Sync", username: MockServers.smbUser, password: MockServers.smbPassword,
            port: MockServers.smbPort
        )
        let progress = try #require(library.progress)
        let transfer = LibraryTransfer(
            archive: LibraryArchive(progress: progress, covers: CoverOverrideStore()), secrets: CredentialStore()
        )
        let state = LibrarySyncState(defaults: defaults)
        let runner = LibrarySyncRunner(
            places: places, placeFor: { _ in SmbSyncPlace(address: address) },
            sync: { try await transfer.sync(with: $0, state: state, appVersion: "0") }
        )
        let sync = MacSync(runner: runner, latestChange: { Date() })
        let clock = ContinuousClock()
        let began = clock.now
        let outcome = await sync.atQuit()
        ConformanceLog.note("sync to a share", "\(outcome), \(runner.status), in \(clock.now - began)")
        #expect(outcome == .synced)
        if case .synced = runner.status {} else {
            Issue.record("the share did not take the document: \(String(describing: runner.status))")
        }
    }

    @Test("With sync off, start settles at once and quit writes nothing")
    func off() async {
        let sync = MacSync(runner: nil, latestChange: { Date() })
        sync.start {}
        #expect(sync.hasSettledStart)
        #expect(await sync.atQuit() == .off)
    }
}
