import AppKit
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The UI walk task 1.14 asks for, run inside the app: the library window is open, and the
    /// preferences open on the system's own action and open once.
    ///
    /// AppKit windows rather than SwiftUI views, because what a reader sees is a window. The
    /// sidebar and the empty states are proved by `CaptureTests`' frames, not by a class name.
    @MainActor
    @Suite("Shell")
    struct ShellTests {
        @Test("The library window is open at launch, resizable, with the documented minimum")
        func libraryWindowIsOpen() throws {
            let window = try #require(ShellWalk.waitForLibraryWindow())

            #expect(window.isVisible)
            #expect(window.styleMask.contains(.resizable))
            #expect(window.contentMinSize.width >= LibraryWindow.minimumSize.width)
            #expect(window.contentMinSize.height >= LibraryWindow.minimumSize.height)
        }

        @Test("The settings action opens one preferences window, and a second call opens no other")
        func settingsOpenOnce() throws {
            let before = ShellWalk.visibleWindows()

            ShellWalk.openSettings()
            let settings = try #require(ShellWalk.waitForNewWindow(since: before))

            #expect(settings.isVisible)
            #expect(settings.frame.width == SettingsRoot.width)

            let after = ShellWalk.visibleWindows()
            ShellWalk.openSettings()
            ShellWalk.settle()
            #expect(ShellWalk.visibleWindows().count == after.count)
            settings.close()
        }
    }
}

/// Driving the hosted app's windows, shared with the capture suite.
@MainActor
enum ShellWalk {
    /// `Window(id:)` names its NSWindow after the scene's id.
    static func libraryWindow() -> NSWindow? {
        NSApplication.shared.windows.first {
            $0.isVisible && ($0.identifier?.rawValue.hasPrefix(LibraryWindow.id) ?? false)
        }
    }

    static func visibleWindows() -> [NSWindow] {
        NSApplication.shared.windows.filter(\.isVisible)
    }

    /// What `⌘,` does: the app menu's item with that key equivalent, sent as the menu would.
    ///
    /// Sent through the menu item rather than a selector typed here, so a rename of the
    /// selector in a later SDK fails this walk rather than the walk's assumption.
    static func openSettings() {
        let app = NSApplication.shared
        app.activate()
        let items = app.mainMenu?.items.first?.submenu?.items ?? []
        let item = items.first { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }
        guard let item, let action = item.action else {
            Issue.record("no Settings item with ⌘, in the app menu: \(items.map(\.title))")
            return
        }
        let sent = app.sendAction(action, to: item.target, from: item)
        #expect(sent, "\(action) was not handled by \(String(describing: item.target))")
    }

    static func waitForLibraryWindow() -> NSWindow? {
        wait { libraryWindow() }
    }

    static func waitForNewWindow(since known: [NSWindow]) -> NSWindow? {
        wait { visibleWindows().first { window in !known.contains(window) } }
    }

    /// Runs the main loop until `condition` returns a value, or the timeout passes.
    static func wait<T>(timeout: TimeInterval = 5, for condition: () -> T?) -> T? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if let value = condition() { return value }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return condition()
    }

    /// A few turns of the main loop, for an action whose only sign is a window that does
    /// *not* appear.
    static func settle() {
        for _ in 0..<6 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
    }
}
