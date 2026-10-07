import DesignSystem
import StoryArcCore
import SwiftUI

@main
struct StoryArcMacApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .storyArcTheme()
                .frame(minWidth: 520, minHeight: 400)
        }
        .commands {
            // Placeholder for the reader and library shortcuts a later wave adds.
            CommandGroup(after: .newItem) {}
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            Form {}
                .formStyle(.grouped)
                .frame(width: 480, height: 320)
        }
    }
}
