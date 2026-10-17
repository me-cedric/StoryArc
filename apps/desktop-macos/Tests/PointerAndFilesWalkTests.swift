import AppKit
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The pointer and the files the system hands over, driven in the app's windows.
    ///
    /// Tasks 2.12, 2.18 and 2.21: a click on a page's right edge turns it while the zones are
    /// on, and a reading setting changed with the reader open applies to it at once; files
    /// handed over open in readers, and an archive the app does not read is named.
    @MainActor
    @Suite("Pointer and files walk")
    struct PointerAndFilesWalkTests {
        @Test("A click on the right edge turns the page, and turning the zones off stops it at once")
        func edgeClick() async throws {
            let library = try await Walk.fixtureLibrary()
            let publication = try #require(Walk.publication(named: "natural-sort", in: library))
            let target = try #require(library.target(for: publication))
            let store = try #require(library.progress)
            try await store.forget(publication.identity)
            let settings = MacSettings.shared
            let zonesWereOn = settings.settings.turnPagesByTappingTheEdges
            defer { settings.settings.turnPagesByTappingTheEdges = zonesWereOn }
            settings.settings.turnPagesByTappingTheEdges = true

            try Walk.open(target)
            let window = try #require(await Walk.until { Walk.readerWindows(for: target).first })
            // A click on a window of an inactive app only activates it, as on any Mac, so the
            // app is activated the way a click on its Dock icon does and the window made key.
            await Walk.activate(window)
            try await Task.sleep(for: .milliseconds(800))
            Walk.click(atFraction: 0.92, in: window)
            try await Task.sleep(for: .milliseconds(600))
            // The setting changes in the preferences while this reader stays open.
            settings.settings.turnPagesByTappingTheEdges = false
            try await Task.sleep(for: .milliseconds(300))
            Walk.click(atFraction: 0.92, in: window)
            try await Task.sleep(for: .milliseconds(600))
            await Walk.close([window])

            // `Walk.close` waits until what the window owed is written.
            let saved = Self.page(try await store.progress(for: publication.identity))
            let held = String(describing: saved)
            #expect(saved == 1, "one turn from the first click and none from the second; the store holds \(held)")
        }

        @Test("Files handed over open in readers, and a CB7 archive beside them is named")
        func filesHandedOver() async throws {
            let library = try await Walk.fixtureLibrary()
            let folder = URL.temporaryDirectory.appending(path: "walk-library", directoryHint: .isDirectory)
            let readable = folder.appending(path: "zip64.cbz")
            let refused = folder.appending(path: "refused.cb7")
            library.dismissRefused()

            // What a drop, a double click in Finder and the Dock menu all do.
            FileInbox.shared.receive([readable, refused])
            let opened = await Walk.until(.seconds(8)) {
                ReaderWindows.shared.open.first { $0.path == readable.standardizedFileURL.path(percentEncoded: false) }
            }
            let target = try #require(opened, "zip64.cbz did not open in a reader")
            let window = try #require(await Walk.until { Walk.readerWindows(for: target).first })

            #expect(library.refused.map(\.name) == ["refused.cb7"])
            #expect(library.refused.first?.outcome == .unsupported(detected: "CB7"))
            await Walk.close([window])
            library.dismissRefused()
        }

        private static func page(_ record: ReadingProgress?) -> Int? {
            guard let record, case let .page(index, _) = record.position else { return nil }
            return index
        }
    }
}

extension Walk {
    /// Activates the app as a Dock click does, and makes this window key.
    static func activate(_ window: NSWindow) async {
        _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init())
        _ = await until(.seconds(3)) { NSApplication.shared.isActive ? true : nil }
        window.makeKeyAndOrderFront(nil)
        _ = await until(.seconds(2)) { window.isKeyWindow ? true : nil }
    }

    /// A left click at a fraction of the window's width, halfway down its content.
    static func click(atFraction fraction: CGFloat, in window: NSWindow) {
        let bounds = window.contentView?.bounds ?? .zero
        let point = NSPoint(x: bounds.width * fraction, y: bounds.height / 2)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else { continue }
            window.sendEvent(event)
        }
    }
}
