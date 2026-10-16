import Foundation

/// Which windows a command can apply in.
enum CommandScope: Sendable, Equatable {
    case library
    case reader
    case any
}

/// Which menu a command sits in, in menu-bar order.
enum CommandPlace: String, Sendable, CaseIterable {
    case file, edit, view, go, reader
}

/// One menu-bar command: its place, its words and its key.
///
/// `desktop-experience`, *Menus, commands and shortcuts*: every command is in a menu, each
/// frequent one with a Command-key shortcut, and a command that cannot apply is disabled
/// rather than removed so the menus keep one shape in every window. The table is data so
/// `CommandTests` can list it against the spec; `StoryArcMacCommands` draws it. Task 2.10.
///
/// Close Window, Settings, Quit, Minimize and the Edit menu's standard items are the
/// system's own and are not listed: SwiftUI supplies them with their standard keys.
struct MacCommand: Hashable, Sendable, Identifiable {
    enum Modifier: Sendable, Hashable { case command, shift, option, control }

    let id: String
    let menu: CommandPlace
    /// A key in the Mac string catalogue.
    let titleKey: String
    let key: Character?
    let modifiers: Set<Modifier>
    let scope: CommandScope

    /// The key as a reader would read it in a menu: `⇧⌘A`.
    var shortcutLabel: String? {
        guard let key else { return nil }
        var label = ""
        if modifiers.contains(.control) { label += "⌃" }
        if modifiers.contains(.option) { label += "⌥" }
        if modifiers.contains(.shift) { label += "⇧" }
        if modifiers.contains(.command) { label += "⌘" }
        return label + Self.name(of: key)
    }

    private static func name(of key: Character) -> String {
        switch key {
        case "\u{F702}": "←"
        case "\u{F703}": "→"
        case "\u{F700}": "↑"
        case "\u{F701}": "↓"
        default: key.uppercased()
        }
    }

    /// Whether the entry is enabled in a window of this kind.
    func isEnabled(in window: WindowKind) -> Bool {
        switch scope {
        case .any: true
        case .library: window == .library
        case .reader: window == .reader
        }
    }
}

/// The kinds of window a command can be judged against.
enum WindowKind: Sendable, Equatable {
    case library
    case reader
}

/// The whole table, in menu order. Keys follow `docs/designs/desktop/macos.md` section 6.
enum CommandTable {
    static let all: [MacCommand] = [
        MacCommand(id: "openFile", menu: .file, titleKey: "desktop.menu.openFile",
                   key: "o", modifiers: [.command], scope: .any),
        MacCommand(id: "addFolder", menu: .file, titleKey: "desktop.menu.addFolder",
                   key: "a", modifiers: [.command, .shift], scope: .any),
        MacCommand(id: "refreshSources", menu: .file, titleKey: "desktop.menu.refresh",
                   key: "r", modifiers: [.command], scope: .library),
        MacCommand(id: "find", menu: .edit, titleKey: "desktop.menu.find",
                   key: "f", modifiers: [.command], scope: .library),
        MacCommand(id: "viewAsGrid", menu: .view, titleKey: "desktop.menu.viewGrid",
                   key: "1", modifiers: [.command, .option], scope: .library),
        MacCommand(id: "viewAsList", menu: .view, titleKey: "desktop.menu.viewList",
                   key: "2", modifiers: [.command, .option], scope: .library),
        MacCommand(id: "fullScreen", menu: .view, titleKey: "desktop.menu.fullScreen",
                   key: "f", modifiers: [.command, .control], scope: .any),
        MacCommand(id: "goHome", menu: .go, titleKey: "desktop.nav.home",
                   key: "1", modifiers: [.command], scope: .library),
        MacCommand(id: "goLibrary", menu: .go, titleKey: "desktop.nav.library",
                   key: "2", modifiers: [.command], scope: .library),
        MacCommand(id: "goDownloads", menu: .go, titleKey: "desktop.nav.downloads",
                   key: "3", modifiers: [.command], scope: .library),
        MacCommand(id: "continueReading", menu: .go, titleKey: "desktop.menu.continueReading",
                   key: "c", modifiers: [.command, .shift], scope: .library),
        MacCommand(id: "showDetails", menu: .go, titleKey: "desktop.menu.showDetails",
                   key: "i", modifiers: [.command], scope: .library),
        MacCommand(id: "nextPage", menu: .reader, titleKey: "desktop.menu.nextPage",
                   key: "\u{F703}", modifiers: [], scope: .reader),
        MacCommand(id: "previousPage", menu: .reader, titleKey: "desktop.menu.previousPage",
                   key: "\u{F702}", modifiers: [], scope: .reader),
        MacCommand(id: "firstPage", menu: .reader, titleKey: "desktop.menu.firstPage",
                   key: "\u{F700}", modifiers: [.command], scope: .reader),
        MacCommand(id: "lastPage", menu: .reader, titleKey: "desktop.menu.lastPage",
                   key: "\u{F701}", modifiers: [.command], scope: .reader),
        MacCommand(id: "goToPage", menu: .reader, titleKey: "desktop.menu.goToPage",
                   key: "g", modifiers: [.command, .option], scope: .reader),
        MacCommand(id: "singlePage", menu: .reader, titleKey: "desktop.menu.singlePage",
                   key: "1", modifiers: [.command, .option], scope: .reader),
        MacCommand(id: "twoPages", menu: .reader, titleKey: "desktop.menu.twoPages",
                   key: "2", modifiers: [.command, .option], scope: .reader),
        MacCommand(id: "zoomIn", menu: .reader, titleKey: "desktop.menu.zoomIn",
                   key: "+", modifiers: [.command], scope: .reader),
        MacCommand(id: "zoomOut", menu: .reader, titleKey: "desktop.menu.zoomOut",
                   key: "-", modifiers: [.command], scope: .reader),
        MacCommand(id: "fitPage", menu: .reader, titleKey: "desktop.menu.fitPage",
                   key: "0", modifiers: [.command], scope: .reader),
        MacCommand(id: "showControls", menu: .reader, titleKey: "desktop.menu.showControls",
                   key: "h", modifiers: [.command, .shift], scope: .reader),
    ]

    static func command(_ id: String) -> MacCommand? {
        all.first { $0.id == id }
    }

    static func commands(in menu: CommandPlace) -> [MacCommand] {
        all.filter { $0.menu == menu }
    }
}
