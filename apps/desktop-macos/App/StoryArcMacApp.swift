import DesignSystem
import StoryArcCore
import SwiftUI

@main
struct StoryArcMacApp: App {
    var body: some Scene {
        // One `Window`, not a `WindowGroup`: `desktop-experience` gives the app one library
        // window and any number of reader windows, and a group would hand out a second
        // library on ⌘N. The readers are wave 2, as `WindowGroup(for:)`.
        Window("StoryArc", id: LibraryWindow.id) {
            LibraryWindow()
                .storyArcTheme()
                .frame(minWidth: LibraryWindow.minimumSize.width, minHeight: LibraryWindow.minimumSize.height)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 720)
        .commands {
            // The menus of docs/designs/desktop/macos.md section 6 are wave 2.
            CommandGroup(after: .newItem) {}
        }

        // The `Settings` scene gives the StoryArc menu its Settings… item and ⌘, for free,
        // and opens one window however often it is asked.
        Settings {
            SettingsRoot()
                .storyArcTheme()
        }
    }
}
