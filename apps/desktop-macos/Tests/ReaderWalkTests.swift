import AppKit
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The reader windows over the fixture library, driven inside the app.
    ///
    /// Tasks 2.9, 2.11, 2.16 and 2.17: a second open of a publication fronts its window, two
    /// publications read side by side, a key turns the page and the position reaches the
    /// store, full screen comes back to the size it left, and closing writes what is owed.
    @MainActor
    @Suite("Reader walk")
    struct ReaderWalkTests {
        @Test("Two readers open side by side, and a second open of one fronts it")
        func twoReaders() async throws {
            let library = try await Walk.fixtureLibrary()
            let first = try #require(Walk.publication(named: "natural-sort", in: library))
            let second = try #require(Walk.publication(named: "stored-entries", in: library))
            let firstTarget = try #require(library.target(for: first))
            let secondTarget = try #require(library.target(for: second))

            try Walk.open(firstTarget)
            let firstWindow = try #require(await Walk.until { Walk.readerWindows(for: firstTarget).first })
            try Walk.open(secondTarget)
            let secondWindow = try #require(await Walk.until { Walk.readerWindows(for: secondTarget).first })
            try Walk.open(firstTarget)
            await Walk.settle()

            #expect(Walk.readerWindows(for: firstTarget).count == 1)
            #expect(Walk.readerWindows(for: secondTarget).count == 1)
            #expect(firstWindow !== secondWindow)
            #expect(Set(ReaderWindows.shared.savedSessions().map(\.target)) == [firstTarget, secondTarget])

            await Walk.close([firstWindow, secondWindow])
            #expect(ReaderWindows.shared.savedSessions().isEmpty)
        }

        @Test("A key turns the page, and the position is in the store when the window closes")
        func keyTurnsAndCloseWrites() async throws {
            let library = try await Walk.fixtureLibrary()
            let publication = try #require(Walk.publication(named: "natural-sort", in: library))
            let target = try #require(library.target(for: publication))
            let store = try #require(library.progress)
            try await store.forget(publication.identity)

            try Walk.open(target)
            let window = try #require(await Walk.until { Walk.readerWindows(for: target).first })
            // The page view takes focus once the publication has opened.
            try await Task.sleep(for: .milliseconds(800))
            Walk.press("\u{F703}", keyCode: KeyCode.rightArrow, in: window)
            Walk.press("\u{F703}", keyCode: KeyCode.rightArrow, in: window)
            await Walk.close([window])

            // *Closing a reader window*: the position is written before the window is gone, and
            // in any case within the five-second cadence.
            var saved: Int?
            let deadline = ContinuousClock.now + .seconds(6)
            while saved != 2, ContinuousClock.now < deadline {
                saved = try await Self.position(of: publication, in: store)
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(saved == 2, "the store holds page index \(String(describing: saved)) after two right-arrow presses")
        }

        @Test("Full screen is entered and left, and the window gets its size back")
        func fullScreen() async throws {
            let library = try await Walk.fixtureLibrary()
            let publication = try #require(Walk.publication(named: "stored-entries", in: library))
            let target = try #require(library.target(for: publication))

            try Walk.open(target)
            let window = try #require(await Walk.until { Walk.readerWindows(for: target).first })
            // Measured at AppKit's own notifications. A tiling window manager (Amethyst runs
            // on the owner's Mac) re-tiles a resizable window a moment after it leaves full
            // screen, so the frame read later is the tiler's, not the app's.
            let frames = FullScreenFrames(window)
            window.toggleFullScreen(nil)
            let entered = await Walk.until(.seconds(5)) { frames.entered ? true : nil }
            if entered == true {
                // The Space animation runs on after it has entered; a toggle inside it is dropped.
                try await Task.sleep(for: .seconds(1.5))
                window.toggleFullScreen(nil)
                let left = await Walk.until(.seconds(8)) { frames.exited }
                #expect(!window.styleMask.contains(.fullScreen))
                let went = String(describing: frames.before)
                #expect(left?.size == frames.before?.size, "came back at \(String(describing: left)), left at \(went)")
            } else {
                // A test host that the system refuses to activate cannot take a Space; the
                // conformance walk records this, and the menu item is what the user has.
                withKnownIssue("an inactive test host cannot enter full screen") {
                    #expect(entered == true)
                }
            }
            frames.stop()
            await Walk.close([window])
        }

        /// The page index the store holds for a publication, or `nil`.
        private static func position(of publication: Publication, in store: ProgressStore) async throws -> Int? {
            guard let record = try await store.progress(for: publication.identity) else { return nil }
            if case let .page(index, _) = record.position { return index }
            return nil
        }
    }
}

/// The window's frame as it goes into full screen and as it comes out, from the notifications.
@MainActor
private final class FullScreenFrames {
    private(set) var before: NSRect?
    private(set) var entered = false
    private(set) var exited: NSRect?
    private var observers: [any NSObjectProtocol] = []

    init(_ window: NSWindow) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { self.before = window.frame }
            },
            center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { self.entered = true }
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { self.exited = window.frame }
            },
        ]
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }
}
