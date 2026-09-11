package app.storyarc

import android.content.Context
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.catalogue.OpdsOrigin
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.persistence.CertificatePinStore
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
import app.storyarc.feature.library.CataloguePage
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

    private val queues = mutableMapOf<Pair<OpdsOrigin?, OpdsCredential?>, DownloadQueue>()

    /**
     * One download queue per catalogue, built on first use and kept for as long as the app runs.
     *
     * **Why one, and why here.** Two queues over one [DownloadStore] fight: a queue puts back
     * every download the store calls running when it is built, because nothing outside the
     * process carries a transfer -- so a second queue re-queues a row the first is fetching,
     * and both drive one foreground service that stops when its own count reaches zero. The
     * queue also has to outlive every screen: `offline-downloads` requires a transfer to
     * continue after the reader leaves the page and a held queue to "resume automatically" when
     * Wi-Fi returns, and a queue remembered by a composition ends when that composition does.
     *
     * **Why per catalogue rather than one for the whole app.** The queue captures the origin it
     * may send a credential to and the credential it sends. One queue for everything would have
     * to be given a null origin, which confines the `Authorization` header only to the
     * acquisition URL's own origin -- that is, to whatever address the *server* named. `sources`
     * promises that "data leaves the device only to the sources the user configured", so the
     * origin the reader configured is what travels beside their secret.
     *
     * Keyed on the origin **and** the credential, because those two are exactly what is
     * captured: two catalogues on one host that the reader signs into differently are two
     * sources, and they must not share the queue that carries their headers.
     */
    fun queue(page: CataloguePage): DownloadQueue =
        queues.getOrPut(page.origin to page.credential) {
            DownloadQueue(
                context,
                pins,
                downloads,
                credential = { page.credential },
                origin = page.origin,
                // The reader's own choices, read from the store on every pump rather than
                // captured here. Without this the queue answers from `AppSettings.Defaults`,
                // where Wi-Fi-only is off and there is no storage limit -- so it is never
                // held, and a queue that is never held has nothing to resume.
                settings = settings::settings,
            )
        }

    /**
     * How the reader reaches a share.
     *
     * Registered from here because this is where the source registry and the credential
     * store both are; `core:format` stays unaware that SMB exists, which is the only way
     * that dependency can point.
     */
    private fun registerShareAccess() {
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
