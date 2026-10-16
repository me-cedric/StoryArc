import Foundation
import Testing

@testable import StoryArc

/// Folder access that survives App Sandbox, task 1.12 of `desktop-clients`.
///
/// The spy asserts the one thing the iOS store gets wrong on a Mac: every bookmark is
/// minted and resolved with `.withSecurityScope`, and every `start` has exactly one `stop`.
/// The last test uses the real system calls in the sandboxed host, because a wrapper that
/// only satisfies a spy has proved nothing about the sandbox.
@Suite("Mac folder bookmarks")
struct MacFolderBookmarksTests {
    /// Records every option it is asked for, and hands back a bookmark that is the path.
    private final class SpyBookmarking: SecurityScopedBookmarking {
        var creationOptions: [URL.BookmarkCreationOptions] = []
        var resolutionOptions: [URL.BookmarkResolutionOptions] = []
        var resolvedBookmarks: [Data] = []
        var started: [URL] = []
        var stopped: [URL] = []
        var isStaleOnResolve = false
        var startSucceeds = true

        /// The path plus a mint number, so a bookmark minted again is different bytes.
        func bookmarkData(for url: URL, options: URL.BookmarkCreationOptions) throws -> Data {
            creationOptions.append(options)
            return Data("\(url.path())|\(creationOptions.count)".utf8)
        }

        func resolve(_ bookmark: Data, options: URL.BookmarkResolutionOptions) throws -> ResolvedBookmark {
            resolutionOptions.append(options)
            resolvedBookmarks.append(bookmark)
            let minted = String(bytes: bookmark, encoding: .utf8) ?? ""
            let path = minted.split(separator: "|").first.map(String.init) ?? ""
            return ResolvedBookmark(url: URL(filePath: path, directoryHint: .isDirectory), isStale: isStaleOnResolve)
        }

        func startAccessing(_ url: URL) -> Bool {
            started.append(url)
            return startSucceeds
        }

        func stopAccessing(_ url: URL) {
            stopped.append(url)
        }
    }

    private struct Fixture {
        let defaults: UserDefaults
        let name: String
        let spy = SpyBookmarking()

        var bookmarks: MacFolderBookmarks {
            MacFolderBookmarks(defaults: defaults, bookmarking: spy)
        }

        func discard() { defaults.removePersistentDomain(forName: name) }
    }

    private func fresh() throws -> Fixture {
        let name = "mac-bm-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return Fixture(defaults: defaults, name: name)
    }

    private let folder = URL(filePath: "/Volumes/Comics/Saga", directoryHint: .isDirectory)

    @Test("A folder is remembered with a security-scoped bookmark, not a minimal one")
    func createsWithSecurityScope() throws {
        let fixture = try fresh()
        defer { fixture.discard() }

        try fixture.bookmarks.add(folder)

        #expect(fixture.spy.creationOptions == [.withSecurityScope])
    }

    @Test("Restoring resolves with security scope and starts access once per folder")
    func resolvesWithSecurityScope() throws {
        let fixture = try fresh()
        defer { fixture.discard() }
        try fixture.bookmarks.add(folder)

        let restored = fixture.bookmarks.restore()

        #expect(fixture.spy.resolutionOptions == [.withSecurityScope])
        #expect(fixture.spy.started == [folder])
        #expect(restored.folders.map(\.url) == [folder])
        #expect(restored.stale.isEmpty)
    }

    @Test("Ending access stops exactly once, however often it is asked")
    func balancesStartAndStop() throws {
        let fixture = try fresh()
        defer { fixture.discard() }
        try fixture.bookmarks.add(folder)
        let access = try #require(fixture.bookmarks.restore().folders.first)

        access.end()
        access.end()

        #expect(fixture.spy.stopped == [folder])
    }

    @Test("Access that is never ended is stopped when the handle goes away")
    func stopsOnRelease() throws {
        let fixture = try fresh()
        defer { fixture.discard() }
        try fixture.bookmarks.add(folder)

        do {
            let restored = fixture.bookmarks.restore()
            #expect(restored.folders.count == 1)
        }

        #expect(fixture.spy.stopped == [folder])
    }

    @Test("A stale bookmark is minted again with security scope and written back")
    func refreshesStaleBookmarks() throws {
        let fixture = try fresh()
        defer { fixture.discard() }
        try fixture.bookmarks.add(folder)
        fixture.spy.isStaleOnResolve = true

        let restored = fixture.bookmarks.restore()

        #expect(restored.folders.map(\.url) == [folder])
        #expect(fixture.spy.creationOptions == [.withSecurityScope, .withSecurityScope])
        // The refreshed bookmark replaces the stale one on disk, under the same key: the
        // next launch resolves the second mint, not the first.
        fixture.spy.isStaleOnResolve = false
        let next = fixture.bookmarks.restore()
        #expect(fixture.spy.resolvedBookmarks.last == Data("\(folder.path())|2".utf8))
        #expect(next.folders.first?.key == restored.folders.first?.key)
        #expect(fixture.spy.creationOptions.count == 2)
    }

    @Test("Access the system refuses is reported stale by name, and never stopped")
    func reportsRefusedAccess() throws {
        let fixture = try fresh()
        defer { fixture.discard() }
        try fixture.bookmarks.add(folder)
        fixture.spy.startSucceeds = false

        let restored = fixture.bookmarks.restore()

        #expect(restored.folders.isEmpty)
        #expect(restored.stale.map(\.name) == ["Saga"])
        #expect(fixture.spy.stopped.isEmpty)
    }

    @Test("Adding the same folder twice keeps one entry")
    func noDuplicates() throws {
        let fixture = try fresh()
        defer { fixture.discard() }

        try fixture.bookmarks.add(folder)
        try fixture.bookmarks.add(folder)

        #expect(fixture.bookmarks.restore().folders.count == 1)
    }

    @Test("Removing by key forgets that folder and no other")
    func removesByKey() throws {
        let fixture = try fresh()
        defer { fixture.discard() }
        let other = URL(filePath: "/Volumes/Comics/Monstress", directoryHint: .isDirectory)
        try fixture.bookmarks.add(folder)
        try fixture.bookmarks.add(other)
        let key = try #require(fixture.bookmarks.restore().folders.first?.key)

        fixture.bookmarks.remove(key: key)

        #expect(fixture.bookmarks.restore().folders.map(\.url) == [other])
    }

    @Test("A real folder in the sandboxed host comes back in a new instance, and access balances")
    func realRoundTrip() throws {
        let name = "mac-bm-real-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = URL.temporaryDirectory.appending(path: "bm-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try MacFolderBookmarks(defaults: defaults).add(folder)

        // A *new* instance, which is what a relaunch is.
        let restored = MacFolderBookmarks(defaults: defaults).restore()
        let access = try #require(restored.folders.first)
        #expect(access.url.standardizedFileURL.path() == folder.standardizedFileURL.path())
        #expect(restored.stale.isEmpty)
        access.end()
    }
}
