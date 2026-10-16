import AppKit
import SwiftUI

/// What the key library window can do, handed to the menu bar through the focus system.
struct LibraryActions {
    let openFile: () -> Void
    let addFolder: () -> Void
    let refresh: () -> Void
    let find: () -> Void
    let viewAsGrid: () -> Void
    let viewAsList: () -> Void
    let go: (LibraryGo) -> Void
    let continueReading: () -> Void
    let showDetails: () -> Void
}

enum LibraryGo { case home, library, downloads }

/// A place the library window is asked to show from outside it.
enum LibraryNavigation: Equatable {
    case go(LibraryGo)
    case search(String)
    case details(publicationID: String)
}

/// What the key reader window can do.
struct ReaderActions {
    let openFile: () -> Void
    let addFolder: () -> Void
    let page: (PageAction) -> Void
    let goToPage: () -> Void
    let singlePage: () -> Void
    let twoPages: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let fitPage: () -> Void
    let showControls: () -> Void
}

extension FocusedValues {
    @Entry var libraryActions: LibraryActions?
    @Entry var readerActions: ReaderActions?
}

/// The menu bar, drawn from `CommandTable`.
///
/// Each entry is enabled when the key window answers it and disabled otherwise, so the
/// menus have one shape in the library and in a reader. Close Window, Settings, Quit, the
/// Edit standard items, Enter Full Screen and the Window menu are SwiftUI's own. Task 2.10.
struct StoryArcMacCommands: Commands {
    @FocusedValue(\.libraryActions) private var library
    @FocusedValue(\.readerActions) private var reader

    var body: some Commands {
        CommandGroup(after: .newItem) {
            item("openFile") { (library?.openFile ?? reader?.openFile)?() }
            item("addFolder") { (library?.addFolder ?? reader?.addFolder)?() }
            Divider()
            item("refreshSources") { library?.refresh() }
        }
        CommandGroup(after: .textEditing) {
            item("find") { library?.find() }
        }
        CommandGroup(before: .toolbar) {
            item("viewAsGrid") { library?.viewAsGrid() }
            item("viewAsList") { library?.viewAsList() }
            Divider()
            // Drawn here rather than left to AppKit, which adds its own only while the View
            // menu is open; `MacAppDelegate` switches that one off so the key is drawn once.
            item("fullScreen") { NSApplication.shared.keyWindow?.toggleFullScreen(nil) }
            Divider()
        }
        CommandMenu(Text("desktop.menu.go")) {
            item("goHome") { library?.go(.home) }
            item("goLibrary") { library?.go(.library) }
            item("goDownloads") { library?.go(.downloads) }
            Divider()
            item("continueReading") { library?.continueReading() }
            item("showDetails") { library?.showDetails() }
        }
        CommandMenu(Text("desktop.menu.reader")) {
            item("nextPage") { reader?.page(.next) }
            item("previousPage") { reader?.page(.previous) }
            item("firstPage") { reader?.page(.first) }
            item("lastPage") { reader?.page(.last) }
            item("goToPage") { reader?.goToPage() }
            Divider()
            item("singlePage") { reader?.singlePage() }
            item("twoPages") { reader?.twoPages() }
            Divider()
            item("zoomIn") { reader?.zoomIn() }
            item("zoomOut") { reader?.zoomOut() }
            item("fitPage") { reader?.fitPage() }
            Divider()
            item("showControls") { reader?.showControls() }
        }
    }

    /// One menu item from the table, enabled when the key window answers its scope.
    @ViewBuilder
    private func item(_ id: String, action: @escaping () -> Void) -> some View {
        if let command = CommandTable.command(id) {
            Button(action: action) {
                Text(LocalizedStringKey(command.titleKey))
            }
            .keyboardShortcut(Self.shortcut(of: command))
            .disabled(!isEnabled(command))
        }
    }

    private func isEnabled(_ command: MacCommand) -> Bool {
        switch command.scope {
        case .any: library != nil || reader != nil
        case .library: library != nil
        case .reader: reader != nil
        }
    }

    static func shortcut(of command: MacCommand) -> KeyboardShortcut? {
        guard let key = command.key else { return nil }
        var modifiers: EventModifiers = []
        if command.modifiers.contains(.command) { modifiers.insert(.command) }
        if command.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if command.modifiers.contains(.option) { modifiers.insert(.option) }
        if command.modifiers.contains(.control) { modifiers.insert(.control) }
        return KeyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
    }
}
