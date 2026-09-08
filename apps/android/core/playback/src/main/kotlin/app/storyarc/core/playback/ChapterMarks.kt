package app.storyarc.core.playback

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.metadata.Chapter
import androidx.media3.inspector.MetadataRetriever
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/**
 * A container's own chapter marks, from a decoder or from the file alone.
 *
 * **One filter, two callers, and that is the whole point of this file.** media3 does not put
 * chapters on `MediaMetadata`. A `Chapter` is a `Metadata.Entry` hung off a track's `Format`,
 * so the marks arrive with the tracks. A playing book reaches those formats through
 * `Player.Listener.onTracksChanged`, and [of] is what `AudiobookSource` calls. A book nobody
 * has opened reaches the *same* formats through [parts], which prepares the media source and
 * resolves its track groups with no player and no audio. Both end in one private mapper, so
 * a second chapter parser cannot drift away from the first.
 *
 * **Why a page needed this at all.** A publication's page draws its chapter list from the
 * playing session, and from the folder's files where nothing plays. A single M4B carries its
 * chapters inside the container and has one file, so before playback the page listed one part
 * and a reader saw no chapters until they had started the book they were choosing.
 *
 * **The `@UnstableApi` opt-in is here and at one place only.** `Chapter`, `Format` and
 * `MetadataRetriever` are all unstable at media3 1.11.0. The opt-in sits on this object, so
 * `AudiobookSource` carries none and no surface above it does either.
 *
 * **`MetadataRetriever` moved in the release this project pins.** 1.10.0 added
 * `androidx.media3.inspector.MetadataRetriever` and deprecated the `exoplayer` one; 1.11.0
 * removed the `exoplayer` one. Checked against the shipped artifacts rather than the plan:
 * the 1.11.0 `media3-exoplayer` class list holds no `MetadataRetriever` at all. The version
 * catalog declares `media3-inspector` at the same version reference.
 */
@OptIn(UnstableApi::class)
object ChapterMarks {

    /** How long a page waits for a container to name its chapters before drawing one part. */
    private const val RETRIEVAL_CEILING_SECONDS = 5L


    /** The marks the decoder reported, alongside the tracks it read. */
    fun of(tracks: Tracks): List<ChapterMark> = marksOf(
        tracks.groups.flatMap { group -> (0 until group.length).map(group::getTrackFormat) },
    )

    /**
     * The parts a file names, read before anything plays it.
     *
     * A retrieval opens the container, prepares one media source and reads its track formats
     * and its length. It decodes no audio and holds no player, so a page can ask this while
     * the listener is still deciding what to hear.
     *
     * **One retrieval answers both halves.** The marks give every chapter but the last its
     * length, and the file's own duration gives the last one its. Asking twice would open the
     * container twice for facts that arrive together.
     *
     * **One part is a valid answer, and so is a file this device cannot read.** An
     * unchaptered audiobook is a normal audiobook — `publication-formats` says so — and
     * [AudiobookChapters.parts] turns no marks into the one part such a book has. A container
     * that fails to open answers the same way, because the page it feeds must state the parts
     * it is sure of rather than nothing at all.
     *
     * @param uri where the audio is, as the platform's data source takes it.
     * @param fallbackTitle what to call the whole of a file that carries no marks.
     * @param chapterWord the reader's own word for a chapter, for marks left untitled.
     */
    suspend fun parts(
        context: Context,
        uri: String,
        fallbackTitle: String,
        chapterWord: String,
    ): List<PlaybackPart> = withContext(Dispatchers.IO) {
        val (marks, totalMicros) = runCatching {
            MetadataRetriever.Builder(context, MediaItem.fromUri(uri)).build().use { reader ->
                // Bounded. A future with no ceiling runs from a page the listener is
                // looking at, and a container the extractor cannot finish reading would hold
                // that page for as long as it liked. A missed deadline is one part, which is
                // what an unchaptered book draws anyway.
                val groups = reader.retrieveTrackGroups()
                    .get(RETRIEVAL_CEILING_SECONDS, TimeUnit.SECONDS)
                val read = marksOf(
                    (0 until groups.length).flatMap { index ->
                        val group = groups.get(index)
                        (0 until group.length).map(group::getFormat)
                    },
                )
                val micros = reader.retrieveDurationUs()
                    .get(RETRIEVAL_CEILING_SECONDS, TimeUnit.SECONDS)
                read to micros.takeIf { it != C.TIME_UNSET }
            }
        }.getOrDefault(emptyList<ChapterMark>() to null)

        AudiobookChapters.parts(
            marks = marks,
            totalMillis = totalMicros?.div(1_000),
            fallbackTitle = fallbackTitle,
            chapterWord = chapterWord,
        )
    }

    private fun marksOf(formats: List<Format>): List<ChapterMark> = formats
        .mapNotNull { it.metadata }
        .flatMap { metadata -> (0 until metadata.length()).map(metadata::get) }
        .filterIsInstance<Chapter>()
        .map { chapter ->
            ChapterMark(
                title = chapter.title?.value,
                startMillis = chapter.startTimeMs,
                // An MP4's chapter track states no end, and media3 says so with
                // `C.TIME_UNSET`. `ChapterMark` says the same thing with null, and
                // `AudiobookChapters` fills it from the next mark.
                endMillis = chapter.endTimeMs.takeIf { it != C.TIME_UNSET },
                isHidden = chapter.isHidden,
            )
        }
}
