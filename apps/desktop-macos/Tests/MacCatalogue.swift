import AppKit
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

/// The Mac's screen catalogue: every screen of the library, the reader and the preferences,
/// over the fixture library, each brought up in its own window at a fixed size.
///
/// The accessibility audit and the snapshot tests both walk it, so a screen added here is
/// audited and held by a reference at once. The library state is set before the walk: the
/// progress store is emptied and one publication is put partway, another finished on a
/// fixed date, so Home has every shelf and draws the same each run.
@MainActor
enum MacCatalogue {
    static let librarySize = NSRect(x: 80, y: 80, width: 1100, height: 720)
    static let readerSize = NSRect(x: 120, y: 60, width: 980, height: 820)
    /// 2026-01-15, the day the seeded publication was finished.
    static let finishedOn = Date(timeIntervalSince1970: 1_768_435_200)

    /// Screens shown with the chrome hidden, where the page alone is drawn and nothing is a control.
    static let chromeless: Set<String> = ["reader-scroll"]

    /// What each screen is handed: its catalogue name and the window that shows it.
    typealias Visit = (_ screen: String, _ window: NSWindow) async throws -> Void

    /// Sets the fixture library to its catalogue state.
    static func prepare() async throws -> (library: MacLibrary, reading: Publication) {
        let library = try await Walk.fixtureLibrary()
        let reading = try #require(Walk.publication(named: "natural-sort", in: library))
        let finished = try #require(Walk.publication(named: "image-pages", in: library))
        let store = try #require(library.progress)
        try await store.clear()
        try await store.save(ReadingProgress(
            identity: reading.identity, position: .page(index: 4, of: 12), updatedAt: finishedOn
        ))
        try await store.save(ReadingProgress(
            identity: finished.identity, position: .page(index: 0, of: 1), updatedAt: finishedOn
        ))
        try await store.mark(finished.identity, finished: true, at: finishedOn)
        await library.refreshProgress()
        library.model.layout = .grid
        return (library, reading)
    }

    /// Brings up each screen in turn and hands it to `visit`.
    static func walk(library: MacLibrary, reading: Publication, _ visit: Visit) async throws {
        _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init())
        _ = await Walk.until(.seconds(3)) { NSApplication.shared.isActive ? true : nil }
        try await libraryScreens(library: library, reading: reading, visit)
        try await readerScreens(library: library, reading: reading, visit)
        try await settingsScreens(visit)
    }

    private static func libraryScreens(library: MacLibrary, reading: Publication, _ visit: Visit) async throws {
        let window = try #require(ShellWalk.waitForLibraryWindow())
        hold(window, at: librarySize)
        defer { release(window) }
        let steps: [(String, () -> Void)] = [
            ("home", { library.navigationRequest = .go(.home) }),
            ("library-grid", { library.model.layout = .grid; library.navigationRequest = .go(.library) }),
            ("library-list", { library.model.layout = .list }),
            ("search", { library.model.layout = .grid; library.navigationRequest = .search("sort") }),
            ("detail", { library.navigationRequest = .details(publicationID: reading.id) }),
        ]
        for (name, step) in steps {
            if name == "detail" {
                library.navigationRequest = .search("")
                try await Task.sleep(for: .milliseconds(300))
                library.navigationRequest = .go(.library)
                try await Task.sleep(for: .milliseconds(500))
            }
            step()
            try await Task.sleep(for: .milliseconds(900))
            try await visit(name, window)
        }
        library.navigationRequest = .root
        try await Task.sleep(for: .milliseconds(300))
        library.navigationRequest = .go(.home)
    }

    private static func readerScreens(library: MacLibrary, reading: Publication, _ visit: Visit) async throws {
        let target = try #require(library.target(for: reading))
        try Walk.open(target)
        let window = try #require(await Walk.until { Walk.readerWindows(for: target).first })
        hold(window, at: readerSize)
        defer { release(window) }
        let state = try #require(await Walk.until { ReaderStates.shared.state(for: target) })
        // Opened and decoded, with the chrome up: it hides three seconds after opening.
        try await Task.sleep(for: .milliseconds(1200))
        try await visit("reader", window)
        // The page browser holds the chrome up while it is open.
        state.isBrowsingPages = true
        try await Task.sleep(for: .milliseconds(900))
        try await visit("reader-pages", window)
        state.isBrowsingPages = false
        state.isAtEnd = true
        try await Task.sleep(for: .milliseconds(500))
        try await visit("reader-end", window)
        state.isAtEnd = false
        state.choose(.verticalScroll)
        // Past the three seconds, so the chrome has hidden and the strip alone shows.
        try await Task.sleep(for: .milliseconds(3500))
        try await visit("reader-scroll", window)
        state.choose(.slide)
        await Walk.close([window])
    }

    private static func settingsScreens(_ visit: Visit) async throws {
        let before = ShellWalk.visibleWindows()
        ShellWalk.openSettings()
        let window = try #require(await Walk.until { ShellWalk.visibleWindows().first { !before.contains($0) } })
        defer {
            MacSettings.shared.settingsTab = .sources
            window.close()
        }
        for tab in [SettingsTab.sources, .appearance, .reading, .privacy, .about] {
            MacSettings.shared.settingsTab = tab
            try await Task.sleep(for: .milliseconds(600))
            window.makeKeyAndOrderFront(nil)
            try await visit("settings-\(tab.rawValue)", window)
        }
    }

    /// Fixes a window's frame. A tiling window manager reasserts the frame of a resizable
    /// window, so the window is made fixed-size for as long as it is held.
    private static func hold(_ window: NSWindow, at frame: NSRect) {
        window.styleMask.remove(.resizable)
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func release(_ window: NSWindow) {
        window.styleMask.insert(.resizable)
    }
}
