import AppKit
import Playback
import StoryArcCore
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The player window over the corpus `chaptered.m4b`, driven inside the app with a
    /// keyboard: space pauses and plays, the arrows skip, the window closes and the session
    /// keeps running until it is ended, and the panel follows. Task 4.7's walk.
    @MainActor
    @Suite("Player walk")
    struct PlayerWalkTests {
        static let publicationID = "walk-audiobook"

        @Test("A chaptered book plays, answers the keys, keeps playing with its window closed, and ends")
        func keyboardAndHiddenWindow() async throws {
            let library = try await Walk.library()
            let target = try Self.freshTarget()
            let centre = PlayerCentre.shared
            if centre.isRunning { centre.end() }

            try Walk.open(target)
            let window = try #require(await Walk.until { Walk.readerWindows(for: target).first })
            // The book is known by its file: a window opened on a file the library does not
            // list carries a placeholder publication whose id is not the target's.
            let isMine = { centre.book?.url.standardizedFileURL == target.url.standardizedFileURL }
            #expect(await Walk.until(.seconds(15)) { isMine() ? true : nil } == true, "the book did not start")
            #expect(centre.isPlaying)
            #expect(centre.parts.count == 3, "the fixture has three chapters, got \(centre.parts.count)")
            #expect(centre.platform is MacPlaybackPlatform)

            // Space pauses and plays, the right arrow skips forward: the keys of the window.
            await Walk.activate(window)
            Walk.press(" ", keyCode: KeyCode.space, in: window)
            #expect(await Walk.until { centre.isPlaying ? nil : true } == true, "space did not pause")
            Walk.press(" ", keyCode: KeyCode.space, in: window)
            #expect(await Walk.until { centre.isPlaying ? true : nil } == true, "space did not play")
            let before = centre.place
            Walk.press("\u{F703}", keyCode: KeyCode.rightArrow, in: window)
            _ = await Walk.until { centre.place != before ? true : nil }
            #expect(centre.place != before, "the right arrow did not skip")

            // *The windows are hidden*: the window goes and the session stays. Paused at the
            // start first, because the fixture is six seconds long and the skip just took it
            // past its end; a session that ran out is not one a window closed.
            centre.play(part: 0, offset: 0)
            centre.pause()
            #expect(centre.isRunning && !centre.isPlaying)
            await Walk.close([window])
            #expect(centre.isRunning, "closing the window ended the session")
            #expect(isMine())

            // A second open of the book fronts a window on the same session, not a restart,
            // and the session plays on from where it was paused.
            try Walk.open(target)
            let again = try #require(await Walk.until { Walk.readerWindows(for: target).first })
            await Walk.settle()
            #expect(isMine() && centre.place.partIndex == 0)
            centre.toggle()
            #expect(centre.isPlaying)
            await Walk.close([again])
            centre.end()
            #expect(!centre.isRunning)
        }

        /// The fixture at a fixed place under one id, with nothing left from an earlier run.
        private static func freshTarget() throws -> ReaderTarget {
            let folder = URL.temporaryDirectory.appending(path: "walk-audiobooks", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "chaptered.m4b")
            if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                try FileManager.default.copyItem(at: TestFixtures.audiobooks.appending(path: "chaptered.m4b"), to: file)
            }
            let target = ReaderTarget(
                publicationID: publicationID, path: file.path(percentEncoded: false), title: "Chaptered"
            )
            let saved = ReaderWindows.shared.savedSessions().map(\.target)
            for stale in saved where stale.publicationID == publicationID { ReaderWindows.shared.didClose(stale) }
            return target
        }
    }
}
