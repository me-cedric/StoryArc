package app.storyarc

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.SourceAction
import app.storyarc.feature.library.clearing
import app.storyarc.feature.library.forgetPinIfUnshared
import app.storyarc.feature.library.readProgress
import app.storyarc.feature.library.removeAfterFinishing
import app.storyarc.feature.library.restore
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
    val context = LocalContext.current

    // Task 17.9: the add-a-source flows the library toolbar used to be the only way to
    // reach. The folder picker and the import picker are each this screen's own launcher,
    // because a launcher is registered where it is used; the three server-backed kinds are
    // already app-level sheets (`AppSheet`), reachable from here exactly as `LibraryDestination`
    // reaches them.
    val pickFolder = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree(),
    ) { tree ->
        if (tree != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            host.library.addFolder(tree)
        }
    }
    val importSource = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { file -> if (file != null) host.library.importFile(file) }

    val store = dependencies.downloads
    val registry by host.library.registry.collectAsStateWithLifecycle()
    // The imported share of the downloads total. Read from the library rather than from the
    // store, because the library is what knows which records are copies the reader brought
    // in. Suspending, so it arrives after the first frame and the row appears with it; the
    // total beside it is a synchronous walk the store can answer at once. iOS's
    // `StoryArcApp` reads the same value from the same accessor.
    var importedBytes by remember { mutableLongStateOf(0L) }
    LaunchedEffect(host.library) { importedBytes = host.library.importedBytes() }
    SettingsScreen(
        settings = settings,
        readerStore = dependencies.readerPreferences,
        opensAtDownloads = screen.opensAtDownloads,
        sources = registry.sources,
        itemCount = { host.library.itemCount(it.id) },
        isPartial = { host.library.isPartial(it.id) },
        readCount = { host.library.readProgress(it.id)?.read },
        readTotal = { host.library.readProgress(it.id)?.total },
        onRemoveSource = { source ->
            // The downloads first. The registry entry is what attributes a download to a
            // source, so deleting the source before its files leaves bytes on disk that
            // nothing in the app can name, let alone offer to remove.
            host.downloads.value =
                removeDownloads(source, dependencies.queue, dependencies.kavitaCards)
            host.library.removeSource(source, dependencies.credentials)
            host.library.forgetPinIfUnshared(source, dependencies.pins, dependencies.pinStore)
        },
        onRenameSource = { source, name -> host.library.renameSource(source, name) },
        onReorderSource = { source, later -> host.library.reorderSource(source, later) },
        onAddFolder = { pickFolder.launch(null) },
        onImportSource = { importSource.launch(arrayOf("*/*")) },
        onAddCatalogue = { host.sheet(AppSheet.AddOnlineLibrary) },
        onAddKavita = { host.sheet(AppSheet.AddKavita) },
        onAddShare = { host.sheet(AppSheet.AddSharedFolder) },
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
                    removeDownloads(source, dependencies.queue, dependencies.kavitaCards)
                SourceAction.REMOVE -> {
                    host.downloads.value =
                        removeDownloads(source, dependencies.queue, dependencies.kavitaCards)
                    host.library.removeSource(source, dependencies.credentials)
                    host.library.forgetPinIfUnshared(source, dependencies.pins, dependencies.pinStore)
                }
            }
        },
        // Read from the store rather than from a browser's acquisition: the store is the
        // record, and Settings can be reached without ever having opened a catalogue.
        downloads = host.downloads.value,
        bytesOnDisk = store.bytesOnDisk(),
        importedBytes = importedBytes,
        // Removing one download and reordering the queue left with the files: both are the
        // Downloads destination's now, which is where a reader looks for them and where
        // they are one tap away rather than four.
        onClearDownloads = {
            // The bytes behind the ten-second undo are staged *inside* the downloads
            // directory, so clearing already takes them with it. Dropping the pending
            // removal is what stops the snackbar going on offering to restore a file that
            // no longer exists. No `settle()`: there is nothing left to delete.
            host.removed.value = null
            // Through the app-level queue, which also stops what it is running -- dl-core 1.1.
            dependencies.queue.clearing()
            host.downloads.value = dependencies.queue.library.value
        },
        // The storage-full hold's own remedy (6.6): takes one finished download off the
        // device, through the same app-level queue and the same ten-second undo as every
        // other removal. The sheet keeps its own copy of the undo state, so this leaves
        // `host.removed` -- the Downloads destination's own snackbar -- untouched.
        onRemoveFinished = { download ->
            val taken = dependencies.queue.removeAfterFinishing(download.id)
            if (taken != null) {
                host.downloads.value = dependencies.queue.library.value
                host.library.refreshImports()
            }
            taken
        },
        onRestoreFinished = { removed ->
            dependencies.queue.restore(removed)
            host.downloads.value = dependencies.queue.library.value
            host.library.refreshImports()
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
