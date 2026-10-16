import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The content types the app opens, for the open panel and the drop targets.
enum MacDocumentTypes {
    static let readable: [UTType] = [
        UTType("app.storyarc.cbz"), UTType("app.storyarc.cbr"), UTType("app.storyarc.cbt"),
        UTType("app.storyarc.cb7"), .epub, .pdf, .zip, .archive,
    ].compactMap { $0 }
}

/// Files the system handed to the app, waiting for a window to open them.
///
/// `application(_:open:)` and the Dock menu arrive outside any SwiftUI scene, and
/// `openWindow` is a view's environment action, so the delegate files the request here and
/// whichever window is up takes it. `WindowOpener` is the action captured by the library
/// window, kept so a request arriving with every window closed still opens a reader.
@MainActor
@Observable
final class FileInbox {
    static let shared = FileInbox()

    private(set) var pending: [URL] = []
    private(set) var serial = 0

    func receive(_ urls: [URL]) {
        pending.append(contentsOf: urls)
        serial += 1
    }

    func take() -> [URL] {
        defer { pending = [] }
        return pending
    }
}

extension View {
    /// Files dropped on this window go to the inbox, which opens each in a reader.
    ///
    /// `desktop-experience`, *Opening files*: a drop on the library or on a reader opens the
    /// file in a reader window; a folder dropped on the library offers to add it.
    func acceptsDroppedFiles() -> some View {
        dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            FileInbox.shared.receive(files)
            return true
        }
    }
}

/// The library window's `openWindow`, captured so the delegate can open readers.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var openReader: ((ReaderTarget) -> Void)?
    var openLibrary: (() -> Void)?
}

/// Every writer with something owed before the app quits.
@MainActor
final class ProgressFlushers {
    static let shared = ProgressFlushers()
    private var writers: [String: ProgressWriter] = [:]

    func register(_ writer: ProgressWriter, for window: String) { writers[window] = writer }
    func unregister(_ window: String) { writers[window] = nil }

    func flushAll() async {
        for writer in writers.values { await writer.flush() }
    }
}

/// What AppKit asks the app directly: files to open, the Dock menu, and the quit.
///
/// `desktop-experience`: a file double-clicked in Finder opens in a reader window; the Dock
/// menu lists the last publications read; every open reader's position is written before
/// the process ends, within five seconds, and the app quits regardless of the result.
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The View menu carries the app's own Enter Full Screen (`StoryArcMacCommands`).
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        FileInbox.shared.receive(urls)
        WindowOpener.shared.openLibrary?()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let recents = RecentPublications().listing()
        for target in recents {
            let item = NSMenuItem(title: target.title, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = target.path
            menu.addItem(item)
        }
        if !recents.isEmpty { menu.addItem(.separator()) }
        let library = NSMenuItem(
            title: String(localized: "desktop.nav.library"), action: #selector(showLibrary), keyEquivalent: ""
        )
        library.target = self
        menu.addItem(library)
        return menu
    }

    @objc private func openRecent(_ item: NSMenuItem) {
        guard let path = item.representedObject as? String else { return }
        FileInbox.shared.receive([URL(filePath: path)])
        WindowOpener.shared.openLibrary?()
    }

    @objc private func showLibrary() {
        WindowOpener.shared.openLibrary?()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            // Five seconds is the spec's own cadence; past it the app quits with what it has.
            let flush = Task { await ProgressFlushers.shared.flushAll() }
            let cap = Task { _ = try? await Task.sleep(for: .seconds(5)) }
            await firstOf(flush, cap)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// The app stays running with its menu bar when the last window closes, as a Mac app does.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { WindowOpener.shared.openLibrary?() }
        return true
    }
}

/// Returns when whichever of the two finishes first; the other is left to finish on its own.
func firstOf(_ first: Task<Void, Never>, _ second: Task<Void, Never>) async {
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await first.value }
        group.addTask { await second.value }
        await group.next()
        group.cancelAll()
    }
}
