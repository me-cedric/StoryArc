import DesignSystem
import EpubReaderFeature
import LibraryFeature
import Persistence
import ReaderFeature
import SettingsFeature
import StoryArcCore
import SwiftUI

@main
struct StoryArcApp: App {
    /// `settings-and-about`: System by default, applied without a restart.
    /// Stored here rather than in a store so the shell has no dependency on a
    /// persistence layer that does not exist yet.
    /// Everything Settings holds, and the store behind it.
    ///
    /// Held here rather than inside the settings screen: `settings-and-about` requires an
    /// appearance to apply "immediately across the whole app without a restart", and
    /// *immediately* means while the reader is still looking at the picker. A screen that
    /// owned its own copy and handed it back on the way out would change the theme one
    /// screen too late.
    ///
    /// It replaces an `@AppStorage("appearanceMode")` that predated the settings store —
    /// two homes for one value, and only one of them was ever written.
    @State private var settings = SettingsStore().settings()
    private let settingsStore = SettingsStore()

    @State private var isShowingSettings = false

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
        _library = State(
            initialValue: LibraryModel(
                progress: store,
                bookmarks: FolderBookmarks(),
                preferences: LibraryPreferences()
            )
        )
    }

    /// The one moment progress is known to have changed. Called when the reader
    /// closes rather than on a timer or on every appearance, because this is the
    /// event — polling for it would be guessing.
    private func refreshProgress() {
        Task { await library.refreshProgress() }
    }

    /// Swaps the reader's contents for the next publication.
    ///
    /// The selection is replaced rather than a second cover presented: stacking
    /// readers would leave a pile of them behind a long series.
    private func openNext(_ publication: Publication) {
        guard let url = library.location(of: publication) else { return }
        reading = ReadingSelection(publication: publication, url: url)
    }

    /// Writes through on every change, so the theme above recomposes with it.
    private var settingsBinding: Binding<AppSettings> {
        Binding(
            get: { settings },
            set: { new in
                settings = new
                settingsStore.save(new)
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(
                model: library,
                progress: progress,
                onOpen: { publication, url in
                    reading = ReadingSelection(publication: publication, url: url)
                },
                onOpenSettings: { isShowingSettings = true }
            )
            .storyArcTheme(appearance: settings.appearance)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(settings: settingsBinding)
                    .storyArcTheme(appearance: settings.appearance)
            }
            .fullScreenCover(item: $reading, onDismiss: refreshProgress) { selection in
                // Full screen, not a sheet: `comic-reader` wants nothing on screen
                // while reading, and a sheet keeps a card edge and the view behind
                // it in view.
                // Two readers, chosen by what the publication *is* rather than by
                // a mode the user picks. A reflowable book is laid out by a
                // rendering engine (ADR-0005); a comic is a list of images and
                // needs none. A fixed-layout EPUB is the third case and belongs
                // with the comic reader — it has pages, at a fixed aspect ratio —
                // which is what `ebook-reader` asks for.
                if selection.publication.format == .epub, !selection.publication.isFixedLayout {
                    EpubReaderView(
                        publication: selection.publication,
                        url: selection.url,
                        progress: progress,
                        preferences: ReaderPreferences()
                    )
                    // Identity, so opening the next issue from the end screen
                    // builds a fresh reader rather than reusing the previous one's
                    // `@State`.
                    .id(selection.publication.id)
                    .storyArcTheme(appearance: settings.appearance)
                } else {
                    ReaderView(
                        publication: selection.publication,
                        url: selection.url,
                        progress: progress,
                        preferences: ReaderPreferences(),
                        // `comic-reader`: the end of one volume offers the next.
                        // The app layer answers this because it is the only place
                        // that can see both the reader and the library.
                        nextInSeries: LibraryIndex.next(
                            after: selection.publication,
                            in: library.publications
                        ),
                        onOpenNext: openNext
                    )
                    .storyArcTheme(appearance: settings.appearance)
                }
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
