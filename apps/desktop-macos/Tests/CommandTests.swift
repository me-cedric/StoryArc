import AppKit
import Testing

@testable import StoryArc

/// The command table of task 2.10, held against the spec's list, and the live menu bar
/// held against the table.
@Suite("Commands")
struct CommandTests {
    /// `desktop-experience`, *Every command is in a menu*, by table id.
    static let spec: [(id: String, shortcut: String?)] = [
        ("openFile", "⌘O"), ("addFolder", "⇧⌘A"), ("find", "⌘F"), ("fullScreen", "⌃⌘F"),
        ("nextPage", "→"), ("previousPage", "←"), ("zoomIn", "⌘+"), ("zoomOut", "⌘-"),
        ("fitPage", "⌘0"), ("goToPage", "⌥⌘G"), ("showControls", "⇧⌘H"),
    ]

    @Test("Every command the spec names is in the table, with its shortcut")
    func specCommandsAreListed() {
        for (id, shortcut) in Self.spec {
            let command = CommandTable.command(id)
            #expect(command != nil, "\(id) is not in the table")
            #expect(command?.shortcutLabel == shortcut, "\(id) has \(command?.shortcutLabel ?? "no key")")
        }
    }

    @Test("A command that cannot apply is disabled in that window, not removed")
    func disabledStatePerWindow() throws {
        let nextPage = try #require(CommandTable.command("nextPage"))
        let goHome = try #require(CommandTable.command("goHome"))
        let openFile = try #require(CommandTable.command("openFile"))

        #expect(!nextPage.isEnabled(in: .library))
        #expect(nextPage.isEnabled(in: .reader))
        #expect(goHome.isEnabled(in: .library))
        #expect(!goHome.isEnabled(in: .reader))
        #expect(openFile.isEnabled(in: .library))
        #expect(openFile.isEnabled(in: .reader))
        // Every entry applies somewhere, so no menu item is dead in both kinds of window.
        #expect(CommandTable.all.allSatisfy { $0.isEnabled(in: .library) || $0.isEnabled(in: .reader) })
    }

    @Test("Ids are unique and every command has a title key")
    func idsAreUnique() {
        let ids = CommandTable.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(CommandTable.all.allSatisfy { !$0.titleKey.isEmpty })
    }

    @Test("The menu bar carries each table command exactly once, with its key equivalent")
    @MainActor
    func menuBarMatchesTable() throws {
        _ = try #require(ShellWalk.waitForLibraryWindow())
        let items = Self.allItems(in: NSApplication.shared.mainMenu)
        for command in CommandTable.all {
            let title = String(localized: String.LocalizationValue(command.titleKey), bundle: .main)
            let matches = items.filter { $0.title == title }
            #expect(matches.count == 1, "\(command.id) (\(title)) appears \(matches.count) times")
            guard let item = matches.first, let key = command.key else { continue }
            #expect(item.keyEquivalentModifierMask == Self.mask(of: command), "\(command.id) modifiers")
            // A digit is placed by the keyboard layout: ⌘1 is ⌘& on a French layout, which
            // is the same key. Every other key is compared as written.
            if !key.isNumber {
                #expect(item.keyEquivalent == String(key).lowercased(), "\(command.id) key is \(item.keyEquivalent)")
            }
        }
        // AppKit's own Enter Full Screen item is switched off, so ⌃⌘F is not drawn twice.
        #expect(!UserDefaults.standard.bool(forKey: "NSFullScreenMenuItemEverywhere"))
        // System items the spec names, supplied by SwiftUI rather than the table.
        #expect(items.contains { $0.keyEquivalent == "w" && $0.keyEquivalentModifierMask == .command })
        #expect(items.contains { $0.keyEquivalent == "q" && $0.keyEquivalentModifierMask == .command })
        #expect(items.contains { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command })
    }

    private static func mask(of command: MacCommand) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if command.modifiers.contains(.command) { mask.insert(.command) }
        if command.modifiers.contains(.shift) { mask.insert(.shift) }
        if command.modifiers.contains(.option) { mask.insert(.option) }
        if command.modifiers.contains(.control) { mask.insert(.control) }
        return mask
    }

    @MainActor
    private static func allItems(in menu: NSMenu?) -> [NSMenuItem] {
        guard let menu else { return [] }
        return menu.items.flatMap { [$0] + allItems(in: $0.submenu) }
    }
}
