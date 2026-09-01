package app.storyarc

import android.content.Context
import app.storyarc.core.catalogue.CertificatePins
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
 */
internal class AppDependencies private constructor(context: Context) {
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
