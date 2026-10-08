package app.storyarc

import android.content.Context
import android.net.Uri
import androidx.annotation.VisibleForTesting
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.lifecycleScope
import app.storyarc.core.format.CoverOverrideStore
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.CertificatePinStore
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.FolderSyncPlace
import app.storyarc.core.persistence.LibraryArchive
import app.storyarc.core.persistence.LibraryPreferences
import app.storyarc.core.persistence.LibrarySyncRunner
import app.storyarc.core.persistence.LibrarySyncState
import app.storyarc.core.persistence.LibraryTransfer
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.ReaderPreferences
import app.storyarc.core.persistence.SettingsStore
import app.storyarc.core.persistence.ShelvesStore
import app.storyarc.core.persistence.SourceStore
import app.storyarc.core.persistence.SyncPlaceChoice
import app.storyarc.core.persistence.SyncPlaceStore
import app.storyarc.core.persistence.SyncStatus
import app.storyarc.core.smb.SmbSyncPlace
import app.storyarc.feature.library.SmbPage
import app.storyarc.feature.library.reloadAfterImport
import app.storyarc.feature.settings.BuildInfo
import kotlinx.coroutines.launch

/**
 * The one sync runner of this process.
 *
 * `library-sync` tasks 2.1 to 4.3. One per process, so the activity and the background job
 * never run two syncs at once. Built over its own store objects: they read and write the same
 * files as the activity's, and the activity reloads what it holds after each sync
 * ([LibrarySyncEffects]). iOS's `StoryArcApp.makeSyncRunner` is the same wiring.
 */
internal object LibrarySyncHub {

    @Volatile private var held: LibrarySyncRunner? = null

    fun runner(context: Context): LibrarySyncRunner =
        held ?: synchronized(this) { held ?: build(context.applicationContext).also { held = it } }

    /** A test hands in a runner over its own place. */
    @VisibleForTesting
    fun install(runner: LibrarySyncRunner?) {
        held = runner
    }

    private fun build(context: Context): LibrarySyncRunner {
        BuildInfo.read(context)
        val credentials = CredentialStore.open(context)
        val sources = SourceStore.open(context)
        val transfer = LibraryTransfer(
            archive = LibraryArchive(
                sources = sources,
                certificatePins = CertificatePinStore.open(context),
                shelves = ShelvesStore.open(context),
                library = LibraryPreferences.open(context),
                settings = SettingsStore.open(context),
                reader = ReaderPreferences.open(context),
                progress = ProgressStore.open(context),
                covers = CoverOverrideStore(CoverOverrideStore.directoryIn(context.filesDir)),
            ),
            secrets = credentials,
        )
        val state = LibrarySyncState.open(context)
        return LibrarySyncRunner(
            places = SyncPlaceStore.open(context),
            placeFor = { choice ->
                when (choice) {
                    is SyncPlaceChoice.Share -> sources.registry().sources
                        .firstOrNull { it.id == choice.sourceId }
                        ?.let { SmbPage.of(it, credentials) }
                        ?.let { SmbSyncPlace(it.address) }
                    is SyncPlaceChoice.Folder -> FolderSyncPlace(context.contentResolver, Uri.parse(choice.tree))
                }
            },
            sync = { place -> transfer.sync(place, state, BuildInfo.version) },
        )
    }
}

/**
 * The foreground trigger, the reload after each sync, and the background job's schedule.
 *
 * `library-sync` task 4.1: each return to the foreground asks for a sync, which the runner
 * throttles to one per 30 seconds. It is launched, so it never holds the first frame. After a
 * sync wrote the stores, the shelves, sources, positions and settings this process holds in
 * memory are read again, so a screen never saves an old copy over what the sync brought.
 */
@Composable
internal fun LibrarySyncEffects(host: AppHost, onSettingsChange: (AppSettings) -> Unit) {
    val runner = LibrarySyncHub.runner(host.activity)
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        host.activity.lifecycleScope.launch { runner.run(LibrarySyncRunner.Trigger.FOREGROUND) }
    }
    LaunchedEffect(runner) {
        runner.status.collect { status ->
            LibrarySyncJob.update(host.activity, isOn = status != SyncStatus.Off)
            if (status is SyncStatus.Synced) {
                onSettingsChange(host.dependencies.settings.settings())
                host.library.reloadAfterImport()
            }
        }
    }
}

/**
 * `library-sync` task 4.2: the reader left [publication], so its position goes to the place at
 * once. A Kavita publication's position goes to Kavita instead.
 */
internal fun AppHost.syncAfterLeaving(publication: Publication) {
    activity.lifecycleScope.launch {
        val ownedByKavita = dependencies.kavitaProgress.origin(publication.id) != null
        LibrarySyncHub.runner(activity).leftPublication(ownedByKavita)
    }
}
