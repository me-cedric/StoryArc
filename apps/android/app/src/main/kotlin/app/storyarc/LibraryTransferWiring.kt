package app.storyarc

import android.content.Context
import app.storyarc.core.format.CoverOverrideStore
import app.storyarc.core.persistence.LibraryArchive
import app.storyarc.core.persistence.LibraryTransfer

/**
 * Export and import of the whole library, over the stores this app already holds.
 *
 * `library-portability`. One store per kind for the whole app, so the archive reads and writes
 * the very objects the screens do rather than a second copy of each. [AppDependencies.credentials]
 * is null where the platform keystore refused to open: nothing is then sealed on export and no
 * secret is written on import, so each source asks for a sign-in. iOS's `StoryArcApp.libraryTransfer`
 * is the same wiring.
 */
internal fun AppDependencies.libraryTransfer(context: Context): LibraryTransfer = LibraryTransfer(
    archive = LibraryArchive(
        sources = sources,
        certificatePins = pinStore,
        shelves = shelves,
        library = libraryPreferences,
        settings = settings,
        reader = readerPreferences,
        progress = progress,
        covers = CoverOverrideStore(CoverOverrideStore.directoryIn(context.filesDir)),
    ),
    secrets = credentials,
)
