package app.storyarc

import android.content.ContentResolver
import android.content.Context
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.model.Publication
import app.storyarc.core.playback.CarBook
import app.storyarc.core.playback.PlaybackHost
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.withContext

/**
 * The audiobooks on this device, written where a car can read them.
 *
 * `audio-playback` asks a car surface to list the library. The system starts `PlaybackService`
 * for that question without starting the app, so the service cannot ask a library that lives
 * in the app — the app must write the answer down first. `PlaybackHost.publishCarLibrary` is
 * that writer, and until this object called it the shelf was empty in every shipped build.
 *
 * **The library's own list is the trigger.** A scan, a finished download and a deletion all
 * change `LibraryViewModel.publications`, so one collector answers all three and no call site
 * has to remember to publish.
 *
 * The seam lives in the app for the reason `OpenedAudiobook` does: `:core:playback` decodes
 * audio and knows nothing about a library, `:feature:library` holds no player, and the app is
 * the one layer entitled to know both exist.
 */
internal object CarShelf {

    /** Republishes the shelf whenever the library changes. Never returns. */
    suspend fun follow(
        context: Context,
        publications: StateFlow<List<Publication>>,
        /** Where a publication's bytes are, as the library recorded it. */
        locate: (Publication) -> String?,
    ) {
        // `collectLatest`, because a scan emits the library once per book found. Each pass
        // walks every audiobook folder on this device, so a plain `collect` would run that
        // walk five hundred times to publish five hundred shelves nobody reads. The last
        // list always finishes, which is the one a car sees.
        publications.collectLatest { library ->
            // Paired on the collecting thread, because the location table is the view model's
            // and is written from the main thread. What crosses to the worker below is a
            // snapshot of two immutable values.
            val located = library.filter { it.format.isAudio }
                .mapNotNull { publication -> locate(publication)?.let { publication to it } }
            val books = withContext(Dispatchers.IO) {
                located.mapNotNull { carBook(it, context.contentResolver) }
            }
            PlaybackHost.publishCarLibrary(context, books)
        }
    }

    /**
     * One row, or null where a car could not start the book.
     *
     * The URIs are `OpenedAudiobook`'s own, in its own order, because a car row plays through
     * the same list the player is handed — a second answer here is a row that starts the wrong
     * file. The id is the publication's for the same reason.
     *
     * A publication still on a server is left out. Its recorded location is an address rather
     * than a file, and a shelf must list what it can play.
     *
     * No length and no artwork: nothing on this side of the app states a book's duration, and
     * `Publication.coverPath` names an entry inside the container rather than a picture the
     * platform can fetch. `audio-playback` allows a row with neither and forbids inventing
     * either.
     */
    private fun carBook(located: Pair<Publication, String>, resolver: ContentResolver): CarBook? {
        val (publication, path) = located
        if (PublicationAccess.isRemote(path)) return null
        val audiobook = OpenedAudiobook.of(publication, path, resolver) ?: return null
        return CarBook(
            id = audiobook.id,
            title = audiobook.title,
            durationMillis = null,
            artworkUri = null,
            uris = audiobook.sources.map { it.uri },
        )
    }
}
