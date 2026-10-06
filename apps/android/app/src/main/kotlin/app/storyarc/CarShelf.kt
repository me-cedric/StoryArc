package app.storyarc

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import app.storyarc.core.format.CoverLadder
import app.storyarc.core.format.CoverOverrideStore
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.playback.CarBook
import app.storyarc.core.playback.PlaybackHost
import app.storyarc.core.playback.PlaybackPosition
import java.io.File
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
        /** Where the listener left off, so a shelf row can carry it. */
        progress: ProgressStore,
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
            // Task 1.3: the car asks the same ladder the shelf does. It used to read
            // `Publication.coverPath` itself, which is the rung below the reader's own
            // picture — so a cover a reader chose appeared on the shelf and not on the
            // car's screen, which is the fourth caller that made one place necessary.
            val ladder = CoverLadder(
                CoverOverrideStore(CoverOverrideStore.directoryIn(context.filesDir)),
            )
            val books = withContext(Dispatchers.IO) {
                located.mapNotNull { carBook(it, context.contentResolver, progress, ladder) }
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
     * No length: nothing on this side of the app states a book's duration, and
     * `audio-playback` allows a row without one and forbids inventing it.
     *
     * The artwork is [carArtworkUri]'s. It used to be null here, with the reason that
     * `Publication.coverPath` named an entry inside the container rather than a picture the
     * platform can fetch — true until task 16.9, and false since: for an audiobook that
     * field is now the file the indexer wrote the embedded artwork to, or the folder's own
     * loose cover image, which is why `CoverLoader` reads it as a file.
     *
     * **The position is `reading-progress`'s, not the shelf's own guess.** `CarLibrary.asPlayed`
     * used to answer every row at its own zero, so a car always offered a finished book's first
     * chapter again. [ListenedPosition.resume] is the same rule the app's own resume button
     * reads, including the one it carries that this needed: a finished book answers null and
     * starts over rather than resuming one page from its end.
     */
    private suspend fun carBook(
        located: Pair<Publication, String>,
        resolver: ContentResolver,
        progress: ProgressStore,
        ladder: CoverLadder,
    ): CarBook? {
        val (publication, path) = located
        if (PublicationAccess.isRemote(path)) return null
        val audiobook = OpenedAudiobook.of(publication, path, resolver) ?: return null
        val resumeAt = carBookPosition(progress.progress(publication.identity))
        return CarBook(
            id = audiobook.id,
            title = audiobook.title,
            durationMillis = null,
            artworkUri = carArtworkUri(ladder.coverFile(publication, path)?.path),
            uris = audiobook.sources.map { it.uri },
            partIndex = resumeAt.partIndex,
            offsetMillis = resumeAt.offsetMillis,
        )
    }
}

/**
 * Where a shelf row resumes, from a publication's stored reading position.
 *
 * Pulled out of [CarShelf.carBook] so the rule a car row needs — a finished book resumes at
 * the beginning, same as one nobody has started, through [ListenedPosition.resume] — is a
 * plain JVM test over [ReadingProgress] rather than one that also needs a `Publication`, a
 * `ContentResolver` and [OpenedAudiobook].
 */
/**
 * The picture a car row carries, and the one the lock screen of a car-started book gets.
 *
 * Task 16.9 reads an audiobook's own artwork at index time and records where it put it, so
 * `coverPath` here is a file and not an entry inside a container. `PlaybackService.browseItem`
 * hands this to `MediaMetadata.setArtworkUri` and `PlaybackHost.attachCarStart` carries it
 * onto the session, which is `audio-playback`'s "the system's own media controls are given
 * that same artwork rather than a second one".
 *
 * A `file://` URI, because that is the one form media3 fetches artwork from. The file is
 * checked first: a cover the system has reclaimed from the cache must leave the row with no
 * artwork rather than with a URI nothing can open.
 */
internal fun carArtworkUri(coverPath: String?): String? =
    coverPath?.let(::File)
        ?.takeIf { it.isFile }
        ?.let { Uri.fromFile(it).toString() }

internal fun carBookPosition(recorded: ReadingProgress?): PlaybackPosition =
    ListenedPosition.resume(recorded?.position, recorded?.isFinished == true)
        ?: PlaybackPosition(partIndex = 0, offsetMillis = 0)
