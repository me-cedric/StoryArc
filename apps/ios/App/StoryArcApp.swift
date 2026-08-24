import DesignSystem
import LibraryFeature
import ReaderFeature
import StoryArcCore
import SwiftUI

@main
struct StoryArcApp: App {
    /// `settings-and-about`: System by default, applied without a restart.
    /// Stored here rather than in a store so the shell has no dependency on a
    /// persistence layer that does not exist yet.
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    /// What the reader is currently showing, if anything.
    ///
    /// The app layer owns this because a feature module never depends on another
    /// feature module (docs/architecture) — the library reports a choice and the
    /// reader accepts one, and neither knows the other exists.
    @State private var reading: ReadingSelection?

    var body: some Scene {
        WindowGroup {
            LibraryView { publication, url in
                reading = ReadingSelection(publication: publication, url: url)
            }
            .storyArcTheme()
            .preferredColorScheme(appearance.colorScheme)
            .fullScreenCover(item: $reading) { selection in
                // Full screen, not a sheet: `comic-reader` wants nothing on screen
                // while reading, and a sheet keeps a card edge and the view behind
                // it in view.
                ReaderView(publication: selection.publication, url: selection.url)
                    .storyArcTheme()
            }
        }
    }
}

/// One publication, chosen for reading.
private struct ReadingSelection: Identifiable {
    let publication: Publication
    let url: URL

    var id: String { publication.id }
}
