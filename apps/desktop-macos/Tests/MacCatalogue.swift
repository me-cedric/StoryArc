import AppKit
import LibraryFeature
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
        // The shelf scanned afresh: a walk that added a server or finished a download leaves
        // rows and titles in the model that removing the source or the download does not take
        // back until a relaunch, and the catalogue draws the fixture library alone.
        // A download a walk finished joins the shelf as a publication of its own, so the
        // downloads are cleared first, as the Downloads tab clears them.
        if let live = MacLibrary.live {
            await live.storage.clear(.downloads)
            live.model.reset()
        }
        let library = try await Walk.fixtureLibrary()
        let reading = try #require(Walk.publication(named: "natural-sort", in: library))
        let finished = try #require(Walk.publication(named: "image-pages", in: library))
        let store = try #require(library.progress)
        try await store.clear()
        // No shelf left by an earlier run that stopped part way: Home draws the catalogue's two.
        let shelves = library.model.shelves
        let leftovers = shelves.collections.map { ShelfPin.collection($0.id) }
            + shelves.lists.map { ShelfPin.list($0.id) }
        await removeShelves(leftovers, of: library)
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
        _ = await AppActivation.activate()
        try await libraryScreens(library: library, reading: reading, visit)
        try await readerScreens(library: library, reading: reading, visit)
        try await settingsScreens(library: library, visit)
    }

    private static func libraryScreens(library: MacLibrary, reading: Publication, _ visit: Visit) async throws {
        let window = try #require(ShellWalk.waitForLibraryWindow())
        hold(window, at: librarySize)
        defer { release(window) }
        // A collection and a reading list, so Home draws its shelves and each page is drawn. The
        // fixtures are named, not taken by id: an id follows the container's path, which
        // follows the user's name, and the references must draw the same on every Mac.
        let shelved = try ["image-pages", "natural-sort", "zip64"].map {
            try #require(Walk.publication(named: $0, in: library)).id
        }
        let collection = try #require(library.createShelf(.collection, named: "Weekend", with: shelved))
        let list = try #require(library.createShelf(.list, named: "Crossover", with: shelved.reversed()))
        let steps: [(String, () async -> Void)] = [
            ("home", { await request(.go(.home), of: library) }),
            ("library-grid", {
                library.model.layout = .grid
                await request(.go(.library), of: library)
            }),
            ("library-list", { library.model.layout = .list }),
            ("search", {
                library.model.layout = .grid
                await request(.search("sort"), of: library)
            }),
            ("downloads", {
                await request(.search(""), of: library)
                seedDownload(in: library)
                await request(.go(.downloads), of: library)
            }),
            ("shelf-collection", { await request(.shelf(collection), of: library) }),
            ("shelf-list", { await request(.shelf(list), of: library) }),
            ("detail", { await request(.details(publicationID: reading.id), of: library) }),
        ]
        defer { library.downloads.queue.remove(seededDownload) }
        do {
            try await visitLibrary(steps, of: library, in: window, visit)
        } catch {
            await removeShelves([collection, list], of: library)
            throw error
        }
        // Removed before the next pass draws Home, so each pass draws the same two shelves.
        await removeShelves([collection, list], of: library)
    }

    private static func removeShelves(_ pins: [ShelfPin], of library: MacLibrary) async {
        for pin in pins { await library.deleteShelf(pin) }
    }

    private static func visitLibrary(
        _ steps: [(String, () async -> Void)], of library: MacLibrary, in window: NSWindow, _ visit: Visit
    ) async throws {
        for (name, step) in steps {
            if name == "detail" {
                await request(.search(""), of: library)
                try await Task.sleep(for: .milliseconds(300))
                await request(.go(.library), of: library)
                try await Task.sleep(for: .milliseconds(500))
            }
            await step()
            try await Task.sleep(for: .milliseconds(900))
            try await visit(name, window)
        }
        await request(.root, of: library)
        try await Task.sleep(for: .milliseconds(300))
        await request(.go(.home), of: library)
    }

    static let seededDownload = "catalogue-finished-download"

    /// One finished download, so the Downloads screen draws a row and its size. Removed after.
    private static func seedDownload(in library: MacLibrary) {
        guard let remote = URL(string: "http://127.0.0.1/catalogue.cbz") else { return }
        library.downloads.queue.record(Download(
            id: seededDownload, title: "Fine Print", remote: remote, mediaType: "application/vnd.comicbook+zip",
            state: .finished, expectedBytes: 1_258_291, downloadedBytes: 1_258_291, completedAt: finishedOn
        ))
    }

    /// Asks the library window to go somewhere, and waits until it has taken the request.
    ///
    /// The window acts on a *change* of the request. One left unread by an earlier walk, the
    /// same as the one asked for now, would be no change at all, and the window would stay
    /// where that walk left it: Home drawn as the library grid, half the pixels wrong. So a
    /// request still pending is cleared first.
    ///
    /// Asked again, up to three times: a request set in the same turn as a redraw that a
    /// seeded record started was seen to go unread once in a run of three (2026-10-17).
    private static func request(_ navigation: LibraryNavigation, of library: MacLibrary) async {
        var taken: Bool?
        for _ in 0..<3 where taken == nil {
            if library.navigationRequest != nil {
                library.navigationRequest = nil
                await Walk.settle()
            }
            library.navigationRequest = navigation
            taken = await Walk.until(.seconds(4)) { library.navigationRequest == nil ? true : nil }
        }
        #expect(taken == true, "the library window did not take \(navigation)")
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

    private static func settingsScreens(library: MacLibrary, _ visit: Visit) async throws {
        let before = ShellWalk.visibleWindows()
        ShellWalk.openSettings()
        let window = try #require(await Walk.until { ShellWalk.visibleWindows().first { !before.contains($0) } })
        defer {
            MacSettings.shared.settingsTab = .sources
            window.close()
        }
        // The Downloads tab draws live sizes and the live connection; the catalogue pins both.
        library.storage.pinned = MacStorage.Sizes(downloads: 1_258_291, covers: 44_032, records: 3_276_800)
        library.downloads.monitor.note(.unmetered)
        defer {
            library.storage.pinned = nil
            Task { await library.storage.refresh() }
        }
        for tab in [SettingsTab.sources, .appearance, .reading, .downloads, .privacy, .about] {
            MacSettings.shared.settingsTab = tab
            try await Task.sleep(for: .milliseconds(600))
            window.makeKeyAndOrderFront(nil)
            try await visit("settings-\(tab.rawValue)", window)
            if tab == .sources { try await sourceSheets(library: library, on: window, visit) }
            if tab == .privacy { try await diagnosticSheet(on: window, visit) }
        }
    }

    /// The diagnostic sheet over the Privacy tab, with an export built from fixed inputs and
    /// the system's version left out, so the image does not follow a minor update. Task 3.14.
    private static func diagnosticSheet(on window: NSWindow, _ visit: Visit) async throws {
        let text = MacDiagnostic.text(
            settings: AppSettings(), sources: SourceRegistry(), cacheBytes: 0, historyBytes: 0
        )
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("platform = ") ? "platform = macOS" : String($0) }
            .joined(separator: "\n")
        MacSettings.shared.diagnostic = DiagnosticText(text: text)
        let sheet = try #require(await Walk.until { window.attachedSheet }, "the diagnostic sheet did not open")
        try await Task.sleep(for: .milliseconds(700))
        try await visit("diagnostic", sheet)
        MacSettings.shared.diagnostic = nil
        _ = await Walk.until { window.attachedSheet == nil ? true : nil }
        try await Task.sleep(for: .milliseconds(300))
    }

    /// The three add sheets, empty, over the Sources tab. Wave 3, task 3.10.
    private static func sourceSheets(library: MacLibrary, on window: NSWindow, _ visit: Visit) async throws {
        let servers = library.servers
        servers.discoversShares = false
        servers.resetSheets()
        defer { servers.discoversShares = true }
        let sheets: [(AddedSource, String)] = [
            (.share, "source-share"), (.catalogue, "source-catalogue"), (.kavita, "source-kavita"),
        ]
        for (kind, name) in sheets {
            servers.adding = kind
            let sheet = try #require(await Walk.until { window.attachedSheet }, "the \(name) sheet did not open")
            try await Task.sleep(for: .milliseconds(700))
            try await visit(name, sheet)
            servers.adding = nil
            _ = await Walk.until { window.attachedSheet == nil ? true : nil }
            try await Task.sleep(for: .milliseconds(300))
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
