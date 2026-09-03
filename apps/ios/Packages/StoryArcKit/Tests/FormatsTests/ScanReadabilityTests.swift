import Foundation
import Synchronization
import Testing

@testable import Formats

/// A walk that saw nothing is two different facts, and until now it wore one face.
///
/// `sources`' metadata cache asks for "a single unobtrusive indicator" saying the shelf is
/// cached. It must stay up when a walk saw nothing *because it could see nothing*, and leave
/// only when a walk genuinely found an empty folder — and `ScanEvent.finished(found:skipped:)`
/// reports `0, 0` for both. A reader whose folder permission lapsed was told their library
/// was empty.
///
/// Android's `ScanReadabilityTest` asserts the same cases, case for case.
@Suite("Scan readability")
struct ScanReadabilityTests {

    // MARK: - The two walks that both saw nothing

    @Test("A walk over a folder that genuinely holds nothing reports no unreadable folder")
    func emptyFolderIsReadable() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let walk = await self.walk(root)

        #expect(walk.unreadable.isEmpty)
        #expect(walk.events == [.finished(found: 0, skipped: 0)])
    }

    @Test("A walk over a folder that does not exist reports it as unreadable")
    func missingFolderIsUnreadable() async {
        // The state a restored bookmark lands in when the folder behind it has gone. The
        // walk finds nothing either way; only this says which nothing it was.
        let missing = URL(fileURLWithPath: "/nowhere/at/all")

        let walk = await self.walk(missing)

        #expect(walk.unreadable == [LibraryScanner.normalized(missing)])
        #expect(walk.events == [.finished(found: 0, skipped: 0)])
    }

    @Test("A walk over a folder the app may not read reports it as unreadable")
    func unreadableFolderIsReported() async throws {
        // The lapsed permission itself, which is the case task 5.1 names: the folder is
        // there, it may well be full, and the app cannot list it.
        let root = try temporaryFolder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path())
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: root.path())
        // Loud rather than silent: a process that can read a mode-0 directory — root — would
        // make every assertion below vacuous, and a vacuous test is worse than none.
        try #require(!FileManager.default.isReadableFile(atPath: root.path()))

        let walk = await self.walk(root)

        #expect(walk.unreadable == [LibraryScanner.normalized(root)])
        #expect(walk.events == [.finished(found: 0, skipped: 0)])
    }

    @Test("The finished event alone cannot tell the two apart")
    func finishedEventIsTheSameForBoth() async throws {
        // The defect, stated as an assertion. Both walks end identically, so any caller
        // reading only the terminal event is deciding between an emptied library and a
        // folder it cannot see by guessing — which is what the cached notice used to do.
        let empty = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: empty) }

        let readable = await walk(empty)
        let unreadable = await walk(URL(fileURLWithPath: "/nowhere/at/all"))

        #expect(readable.events == unreadable.events)
        #expect(readable.unreadable != unreadable.unreadable)
    }

    // MARK: - A partial walk is not an empty one

    @Test("A subfolder that cannot be read makes the walk partial, not empty")
    func unreadableSubfolderIsReported() async throws {
        // What the walk did not see is unaccounted for rather than gone, which is why this
        // is reported per directory rather than as one flag about the root. A caller that
        // removed every publication it did not meet would drop a whole series here.
        let root = try temporaryFolder()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: root.appending(path: "Locked").path()
            )
            try? FileManager.default.removeItem(at: root)
        }
        let locked = root.appending(path: "Locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: FixtureCorpus.url("comics/single-page.cbz"),
            to: root.appending(path: "01.cbz")
        )
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path())
        try #require(!FileManager.default.isReadableFile(atPath: locked.path()))

        let walk = await self.walk(root)

        #expect(walk.unreadable == [LibraryScanner.normalized(locked)])
        // The root was readable, so what it did hold is still found. A partial walk is worth
        // its findings; it is only not worth trusting about what is missing.
        #expect(walk.events.compactMap(\.publication).count == 1)
        #expect(walk.events.last == .finished(found: 1, skipped: 0))
    }

    @Test("A walk that read every directory it visited reports nothing")
    func fullyReadableWalkReportsNothing() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let series = root.appending(path: "Bone")
        try FileManager.default.createDirectory(at: series, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: FixtureCorpus.url("comics/single-page.cbz"),
            to: series.appending(path: "01.cbz")
        )

        let walk = await self.walk(root)

        #expect(walk.unreadable.isEmpty)
        #expect(walk.events.last == .finished(found: 1, skipped: 0))
    }

    // MARK: - Driving the walk

    private struct Walk {
        let events: [ScanEvent]
        let unreadable: [String]
    }

    /// Everything one walk reported, both channels.
    ///
    /// Behind a mutex because the reporter is `@Sendable` and the walk calls it from the task
    /// driving the stream. Named rather than trailing: `known` is a closure parameter too, and
    /// a trailing closure binds to that one instead — which the compiler catches here only
    /// because the two take different types.
    private func walk(_ folder: URL) async -> Walk {
        let unreadable = Mutex<[String]>([])
        var events: [ScanEvent] = []
        let stream = LibraryScanner.scan(
            folderAt: folder,
            onUnreadableFolder: { path in unreadable.withLock { $0.append(path) } }
        )
        for await event in stream { events.append(event) }
        return Walk(events: events, unreadable: unreadable.withLock { $0 })
    }

    private func temporaryFolder() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "readability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
