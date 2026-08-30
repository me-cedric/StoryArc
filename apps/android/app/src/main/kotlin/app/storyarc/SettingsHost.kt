package app.storyarc

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.SourceAction
import app.storyarc.core.persistence.locationOf
import app.storyarc.feature.settings.SettingsScreen
import app.storyarc.navigation.AppSheet
import app.storyarc.navigation.Screen

/**
 * Settings, and everything about it that only the app layer can answer.
 *
 * The registry belongs to the library and a feature module never depends on another feature
 * module, so this layer carries it across and carries the removal back. The download store
 * belongs to this layer outright — which is why the five actions `sources` names on a
 * source's own screen are split here: three are the library's, two touch the downloads.
 * iOS's `StoryArcApp` carries the same switch.
 */
@Composable
internal fun SettingsHost(
    host: AppHost,
    screen: Screen.Settings,
    settings: AppSettings,
    onSettingsChange: (AppSettings) -> Unit,
    onResetSettings: () -> Unit,
    onClose: () -> Unit,
) {
    val dependencies = host.dependencies
    val store = dependencies.downloads
    val registry by host.library.registry.collectAsStateWithLifecycle()
    SettingsScreen(
        settings = settings,
        readerStore = dependencies.readerPreferences,
        opensAtDownloads = screen.opensAtDownloads,
        sources = registry.sources,
        itemCount = { host.library.itemCount(it.id) },
        onRemoveSource = { source ->
            // The downloads first. The registry entry is what attributes a download to a
            // source, so deleting the source before its files leaves bytes on disk that
            // nothing in the app can name, let alone offer to remove.
            host.downloads.value =
                removeDownloads(source, host.downloads.value, store, dependencies.kavitaCards)
            host.library.removeSource(source, dependencies.credentials)
        },
        onRenameSource = { source, name -> host.library.renameSource(source, name) },
        onReorderSource = { source, later -> host.library.reorderSource(source, later) },
        onSourceAction = { source, action ->
            when (action) {
                // Presented rather than run: the answer arrives when the reader has
                // finished typing.
                SourceAction.RECONNECT -> host.sheet(AppSheet.Reconnect(source))
                SourceAction.TEST_CONNECTION ->
                    host.library.testSource(source, dependencies.credentials, dependencies.pins)
                SourceAction.REFRESH ->
                    host.library.refreshSource(source, dependencies.credentials, dependencies.pins)
                SourceAction.CLEAR_CACHE -> host.library.clearSourceCache(source)
                SourceAction.REMOVE_DOWNLOADS -> host.downloads.value =
                    removeDownloads(source, host.downloads.value, store, dependencies.kavitaCards)
                SourceAction.REMOVE -> {
                    host.downloads.value =
                        removeDownloads(source, host.downloads.value, store, dependencies.kavitaCards)
                    host.library.removeSource(source, dependencies.credentials)
                }
            }
        },
        // Read from the store rather than from a browser's acquisition: the store is the
        // record, and Settings can be reached without ever having opened a catalogue.
        downloads = host.downloads.value,
        bytesOnDisk = store.bytesOnDisk(),
        onReorderDownload = { download, later ->
            host.downloads.value = host.downloads.value.moving(download.id, later)
            store.save(host.downloads.value)
        },
        onRemoveDownload = { download ->
            // Asked of the store rather than composed here. The file is named after the
            // publication and filed under its identifier, and composing the path deleted
            // `<id>/<id>.cbz` — a path nothing has been written to since downloads started
            // carrying the reader's own title.
            store.delete(store.locationOf(download))
            host.downloads.value = host.downloads.value.removing(download.id)
            store.save(host.downloads.value)
            // The library holds a row for every imported copy, and a row whose file has
            // just been deleted is a book that opens onto nothing.
            host.library.refreshImports()
        },
        onClearDownloads = {
            // The bytes behind the ten-second undo are staged *inside* the downloads
            // directory, so clearing already takes them with it. Dropping the pending
            // removal is what stops the snackbar going on offering to restore a file that
            // no longer exists. No `settle()`: there is nothing left to delete.
            host.removed.value = null
            host.downloads.value = store.clearing()
        },
        // Written through on every change rather than on the way out.
        // `settings-and-about` requires an appearance to apply immediately, and the state
        // lives above the theme so it recomposes with it — the screen reports, the host
        // holds.
        onChange = onSettingsChange,
        onReset = onResetSettings,
        onClose = onClose,
    )
}
