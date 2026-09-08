package app.storyarc

import android.content.Context
import app.storyarc.core.model.Publication
import app.storyarc.core.playback.ChapterMarks
import app.storyarc.core.playback.NowPlaying
import app.storyarc.core.playback.PartLayout
import app.storyarc.feature.library.AudiobookPart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The parts a publication's page lists, before a listener has started the book.
 *
 * `audio-playback` puts the chapter list on the page rather than in the player, because the
 * player is reached by starting the book — so a listener choosing what to hear next could
 * otherwise see a chapter list only by first playing something they had not chosen.
 *
 * The seam lives in the app for the reason `OpenedAudiobook` does: `:feature:library` holds no
 * player and takes no dependency on one, so the page states the shape it needs and this fills
 * it in.
 */
internal object ListenedChapters {

    /**
     * The parts of [publication], or none where nothing can name them.
     *
     * **The session answers first, when it is this book.** A playing publication has its
     * container's own chapter marks and their lengths, and it is the only answer that also
     * knows where the audio currently is.
     *
     * **A single file is then read, not assumed to have one part.** A folder's parts are its
     * files, and the format layer already ordered and named them. A single M4B carries its
     * chapters in the container, so [ChapterMarks.parts] opens it and asks — which is what a
     * chaptered book needed to list its chapters before it plays rather than after.
     *
     * A folder's parts still state no length. Measuring them means an extractor per file, and
     * `OpenedAudiobook` records why a scan does not pay that; the decoder reports them once
     * the book plays.
     *
     * @param path where the publication's bytes are, as the library recorded it.
     * @param chapterWord the reader's own word for a chapter, for marks a container left
     *   untitled.
     */
    suspend fun of(
        publication: Publication,
        path: String?,
        context: Context,
        playing: NowPlaying?,
        chapterWord: String,
    ): List<AudiobookPart> {
        if (!publication.format.isAudio) return emptyList()
        val session = playing?.takeIf { it.publicationId == publication.id }
        if (session != null) {
            return session.parts.map { AudiobookPart(it.title, it.duration.statedMillis) }
        }
        val location = path ?: return emptyList()
        val book = withContext(Dispatchers.IO) {
            OpenedAudiobook.of(publication, location, context.contentResolver)
        } ?: return emptyList()

        return when (book.layout) {
            PartLayout.FILES -> book.sources.map { AudiobookPart(it.title, statedMillis = null) }
            PartLayout.MARKS -> ChapterMarks.parts(
                context = context,
                uri = book.sources.first().uri,
                fallbackTitle = book.title,
                chapterWord = chapterWord,
            ).map { AudiobookPart(it.title, it.duration.statedMillis) }
        }
    }
}
