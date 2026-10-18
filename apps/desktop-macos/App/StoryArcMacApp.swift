import DesignSystem
import StoryArcCore
import SwiftUI

@main
struct StoryArcMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    @State private var library = MacLibrary()

    var body: some Scene {
        // One `Window`, not a `WindowGroup`: `desktop-experience` gives the app one library
        // window and any number of reader windows, and a group would hand out a second
        // library on ⌘N.
        Window("StoryArc", id: LibraryWindow.id) {
            LibraryWindow(library: library)
                .macChrome()
                .frame(minWidth: LibraryWindow.minimumSize.width, minHeight: LibraryWindow.minimumSize.height)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 720)
        .commands {
            StoryArcMacCommands()
        }

        // One reader per publication: every open goes through `ReaderWindowRegistry`, which
        // fronts the window already reading it. Restoration is the app's own
        // (`RestorationPlan`), so a window whose publication is gone is named, not reopened.
        WindowGroup(for: ReaderTarget.self) { $target in
            if let target {
                ReaderRoot(target: target, library: library)
                    .macChrome()
            }
        }
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 820)

        // The `Settings` scene gives the StoryArc menu its Settings… item and ⌘, for free,
        // and opens one window however often it is asked.
        Settings {
            SettingsRoot(library: library)
                .macChrome()
        }
    }
}
