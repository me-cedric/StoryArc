package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.LibrarySyncRunner
import app.storyarc.core.persistence.ReaderPreferences
import app.storyarc.core.persistence.SyncPlaceChoice
import app.storyarc.core.persistence.SyncPlaceStore

/**
 * The settings the catalogue draws: four sources in four states, and a sync place.
 * No file and no network.
 */
internal object CatalogueSettings {
    private const val DAY = 86_400_000L

    val sources = listOf(
        Source(
            displayName = "Comics folder",
            kind = SourceKind.LOCAL_FOLDER,
            state = SourceConnectionState.Connected,
            lastSuccessfulSyncEpochMillis = 1_760_000_000_000L,
            locator = "content://com.android.externalstorage.documents/tree/primary%3AComics",
        ),
        Source(
            displayName = "Attic Kavita",
            kind = SourceKind.KAVITA_SERVER,
            state = SourceConnectionState.Connected,
            lastSuccessfulSyncEpochMillis = 1_760_000_000_000L - DAY,
            locator = "https://kavita.example.test",
        ),
        Source(
            displayName = "Living room NAS",
            kind = SourceKind.NETWORK_SHARE,
            state = SourceConnectionState.Unreachable(sinceEpochMillis = 1_760_000_000_000L - 2 * DAY),
            locator = "smb://nas.example.test/books",
        ),
        Source(
            displayName = "Standard Ebooks",
            kind = SourceKind.OPDS_CATALOG,
            state = SourceConnectionState.Connected,
            locator = "https://opds.example.test/feed",
        ),
    )

    /** A sync runner whose place is the folder `Sync`, which a test never reaches. */
    fun syncRunner(context: Context): LibrarySyncRunner {
        val runner = LibrarySyncRunner(
            places = SyncPlaceStore.open(context),
            placeFor = { null },
            sync = { error("a catalogue test never syncs") },
        )
        runner.choose(SyncPlaceChoice.Folder("content://com.android.externalstorage.documents/tree/primary%3ASync"))
        return runner
    }

    /** The settings screen over these sources, opening at the list of groups. */
    @Composable
    fun Screen(withSync: Boolean = false) {
        val context = LocalContext.current
        SettingsScreen(
            settings = AppSettings(),
            onChange = {},
            readerStore = ReaderPreferences(
                context.getSharedPreferences("catalogue-settings", Context.MODE_PRIVATE),
            ),
            onReset = {},
            onClose = {},
            sources = sources,
            itemCount = { source -> source.displayName.length * 7 },
            bytesOnDisk = 312_000_000L,
            syncRunner = if (withSync) syncRunner(context) else null,
        )
    }
}
