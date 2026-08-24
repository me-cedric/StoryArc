import DesignSystem
import LibraryFeature
import Persistence
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

    /// One store for the whole app. ADR-0006 makes the local record authoritative,
    /// so the reader writing and the library reading have to be the same store —
    /// two would disagree about where the user is.
    private let progress: ProgressStore?

    /// Held here so the app can refresh it when the reader closes.
    @State private var library: LibraryModel

    init() {
        let store = try? ProgressStore()
        self.progress = store
        _library = State(initialValue: LibraryModel(progress: store))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(model: library, progress: progress) { publication, url in
                reading = ReadingSelection(publication: publication, url: url)
            }
            .storyArcTheme()
            .preferredColorScheme(appearance.colorScheme)
            .fullScreenCover(item: $reading, onDismiss: {
                // The one moment progress is known to have changed. Refreshed here
                // rather than on a timer or on every appearance, because this is
                // the event, and polling for it would be guessing.
                Task { await library.refreshProgress() }
            }) { selection in
                // Full screen, not a sheet: `comic-reader` wants nothing on screen
                // while reading, and a sheet keeps a card edge and the view behind
                // it in view.
                ReaderView(
                    publication: selection.publication,
                    url: selection.url,
                    progress: progress
                )
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
