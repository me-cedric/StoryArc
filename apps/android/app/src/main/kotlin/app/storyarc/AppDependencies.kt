package app.storyarc

import android.content.Context
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.format.HttpSource
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.persistence.CertificatePinStore
import app.storyarc.core.persistence.CleanupChoices
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.KavitaCardStore
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.LibraryPreferences
import app.storyarc.core.persistence.PlaybackPreferences
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.ReaderPreferences
import app.storyarc.core.persistence.ScanJournal
import app.storyarc.core.persistence.SettingsStore
import app.storyarc.core.persistence.ShelvesStore
import app.storyarc.core.persistence.SourceStore
import app.storyarc.core.smb.SmbClient
import app.storyarc.feature.library.DownloadQueue
import app.storyarc.feature.library.SmbLocator
import app.storyarc.feature.library.SmbPage

/**
 * Every store the app opens, opened once.
 *
 * One store per kind for the whole app, which ADR-0006 requires rather than merely prefers:
 * the local record is authoritative, so the reader writing a position and the library
 * reading one have to be the same object. Two would disagree about where the reader is.
 *
 * Gathered here rather than in `onCreate` because a screen that needs six of them should
 * take one parameter, and because the composition can then be given the whole set without
 * the activity threading each one through by hand.
 *
 * The download queues live here for the same reason a store does, which [queue] sets out: one
 * per catalogue, and each one has to outlive every screen that starts a transfer.
 */
internal class AppDependencies private constructor(private val context: Context) {
    val progress: ProgressStore = ProgressStore.open(context)
    val libraryPreferences: LibraryPreferences = LibraryPreferences.open(context)
    val readerPreferences: ReaderPreferences = ReaderPreferences.open(context)
    val playbackPreferences: PlaybackPreferences = PlaybackPreferences.open(context)
    val settings: SettingsStore = SettingsStore.open(context)
    val sources: SourceStore = SourceStore.open(context)
    val shelves: ShelvesStore = ShelvesStore.open(context)
    /**
     * Null where the platform keystore refuses to open, which `sources` treats as a source
     * with no secret rather than as a failure: the library still browses, and only the
     * screens that need a secret say so.
     */
    val credentials: CredentialStore? = CredentialStore.open(context)
    val pinStore: CertificatePinStore = CertificatePinStore.open(context)

    /**
     * One pin set for the whole app, loaded once. Shared between adding a catalogue and
     * browsing one on purpose: a certificate the reader accepted while adding a server has
     * to still be accepted when its covers load.
     */
    val pins: CertificatePins = CertificatePins(pinStore.pins())

    val downloads: DownloadStore = DownloadStore.open(context)
    /** D7's "Keep" action on the end screen. */
    val cleanupChoices: CleanupChoices = CleanupChoices.open(context)
    val kavitaProgress: KavitaProgressStore = KavitaProgressStore.open(context)

    /**
     * What each Kavita server said about the downloads it produced. Held because removing a
     * source removes its downloads, and what was cached about them goes too.
     */
    val kavitaCards: KavitaCardStore = KavitaCardStore.open(context)

    /**
     * What an interrupted scan wrote down, so the next one picks up rather than starting
     * again. `local-library` requires a scan to be "cancellable and resumable".
     */
    val scanJournal: ScanJournal = ScanJournal.open(context)

    /**
     * The one app-level download queue, built on first use and kept for as long as the app
     * runs -- the only writer of [downloads].
     *
     * **The bug this closes.** A queue keyed per catalogue -- by the origin and the credential
     * it was given -- held its own in-memory copy of [downloads]' records. Two of them open at
     * once, or one of them beside a screen with no queue of its own writing [DownloadStore]
     * directly, each saved over whatever the other had just written: a Stop that did not reach
     * the running transfer, a Kavita keep or a source removal undone by the next catalogue's
     * queue pumping. One instance, asked for however many catalogues are open, is what removes
     * the race rather than narrowing it.
     *
     * **Multiple sources, one queue.** The queue used to capture one source's origin and
     * credential at construction, which a single app-wide instance cannot do: it runs
     * downloads for every source at once. [DownloadQueue.enqueue] and its neighbours take the
     * source explicitly instead, from the page that knows it, and [credentialFor] resolves a
     * transfer's credential from the record's own source id rather than from one source pinned
     * to the queue -- the origin itself needs no such change, because [app.storyarc.core.catalogue.OpdsClient]
     * already falls back to the address's own origin when none is fixed on it.
     */
    val queue: DownloadQueue by lazy {
        DownloadQueue(
            context,
            pins,
            downloads,
            credential = ::credentialFor,
            // The reader's own choices, read from the store on every pump rather than
            // captured here. Without this the queue answers from `AppSettings.Defaults`,
            // where Wi-Fi-only is off and there is no storage limit -- so it is never
            // held, and a queue that is never held has nothing to resume.
            settings = settings::settings,
        )
    }

    /**
     * A transfer's credential, resolved from the record's own source rather than from a
     * single source fixed on the queue.
     *
     * A fresh [downloads] read rather than the queue's own state: this closure is built
     * before the queue that will call it exists, so it cannot capture the queue, and asking
     * disk once per attempted transfer is the cost of a queue that is no longer one
     * catalogue's own.
     */
    private fun credentialFor(downloadId: String): OpdsCredential? {
        val sourceId = downloads.library()[downloadId]?.sourceId ?: return null
        val source = sources.registry().sources.firstOrNull { it.id == sourceId } ?: return null
        return source.credentialReference?.let { credentials?.secret(it) }?.let(OpdsCredential::of)
    }

    /**
     * How the reader reaches a share, and an address that is still arriving.
     *
     * Registered from here because this is where the source registry and the credential
     * store both are; `core:format` stays unaware that SMB exists, which is the only way
     * that dependency can point.
     */
    private fun registerShareAccess() {
        // `offline-downloads`' *Reading while downloading*. Without this line the ranged
        // reader is built, tested and unreachable: nothing else registers `http`, so an
        // acquisition URL handed to `PublicationAccess` would be opened as a local file.
        HttpSource.register()

        PublicationAccess.register("smb") { path ->
            val source = sources.registry().sources
                .firstNotNullOfOrNull { candidate ->
                    SmbPage.of(candidate, credentials)?.takeIf {
                        path.startsWith(SmbLocator.of(it.address))
                    }
                }
                // The path is deliberately not interpolated: a share path names a
                // reader's machine and their folders, and this string can reach a crash
                // report. Carried over from the call site this moved out of.
                ?: error("no share holds ${'$'}path")
            val inside = path.removePrefix(SmbLocator.of(source.address)).trim('/')
            SmbClient(source.address).open(inside)
        }
    }

    companion object {
        /** Opened against the application context, so nothing here outlives its own owner. */
        fun open(context: Context): AppDependencies =
            AppDependencies(context.applicationContext).apply { registerShareAccess() }
    }
}
