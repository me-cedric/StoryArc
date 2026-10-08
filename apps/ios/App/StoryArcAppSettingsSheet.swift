import Catalogue
import DesignSystem
import EpubReaderFeature
import LibraryFeature
import Persistence
import Playback
import ReaderFeature
import SettingsFeature
import Formats
import Smb
import StoryArcCore
import SwiftUI

/// What the Settings sheet shows, with the actions the app layer resolves for it.
///
/// Split out of `StoryArcApp.swift`, which had passed the 400-line cap.
extension StoryArcApp {
    var settingsSheet: some View {
        SettingsView(
            settings: settingsBinding,
            readerStore: ReaderPreferences(),
            onReset: resetSettings,
            opensAtDownloads: isShowingDownloads,
            sources: library.registry.sources,
            itemCount: { library.itemCount(of: $0) },
            isPartial: { library.isPartial($0) },
            readCount: { library.readProgress(of: $0)?.read },
            readTotal: { library.readProgress(of: $0)?.total },
            onRemoveSource: removeSource,
            onRenameSource: { library.rename($0, to: $1) },
            onAddFolder: { settingsPicking = .folder },
            onImportSource: { settingsPicking = .file },
            onAddCatalogue: { settingsAddingSource = .catalogue },
            onAddKavita: { settingsAddingSource = .kavita },
            onAddShare: { settingsAddingSource = .share },
            onReorderSource: { library.move($0, to: $1) },
            onSourceAction: { await perform($1, on: $0) },
            // Read from the store rather than from a browser's acquisition: the
            // store is the record, and Settings can be reached without ever having
            // opened a catalogue.
            downloads: downloads,
            bytesOnDisk: downloadStore.bytesOnDisk(),
            // The imported share of that total. `local-library` asks the app to
            // report the space an import used, and this is the only screen that
            // states a storage figure at all. Android's `SettingsHost` reads the
            // same value from the same accessor.
            importedBytes: library.importedBytes,
            // Removing one download and reordering the queue left with the files:
            // both are the Downloads destination's now, which is where a reader
            // looks for them and where they are one tap away rather than four.
            onClearDownloads: {
                // The bytes behind the undo are staged *inside* the downloads
                // directory, so clearing already takes them with it. Dropping the
                // pending removal is what stops a later undo putting a record back
                // for bytes nobody has. Android has the same two lines.
                removedDownload = nil
                DownloadQueue.shared().clearing()
                downloads = DownloadQueue.shared().library
            },
            onRemoveFinished: removeFinished,
            onRestoreFinished: restoreFinished,
            libraryTransfer: libraryTransfer,
            onLibraryImported: libraryImported
        )
            .storyArcTheme(appearance: settings.appearance)
            .speaking(settings.language)
            // Task 17.9: the same two presentations `LibraryView` mounts for its own
            // add button, mounted a second, independent time over Settings.
            .pickingLocalLibrary(into: library, pick: $settingsPicking)
            .addingSources(to: library, pins: .app, sheet: $settingsAddingSource)
            // Over Settings, because that is where the action was pressed and the
            // reader has not asked to leave the screen they were diagnosing.
            .sheet(item: $reconnecting) { source in
                SourceReconnectSheet(source: source) { reconnected in
                    library.reconnect(reconnected)
                    reconnecting = nil
                }
                .storyArcTheme(appearance: settings.appearance)
                .speaking(settings.language)
            }
    }
}
