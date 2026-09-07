package app.storyarc

import android.content.ContentResolver
import app.storyarc.core.model.Publication
import app.storyarc.core.playback.NowPlaying
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
     * container's own chapter marks and their lengths, which is the only place a stated
     * duration comes from; a folder read from disk carries its part titles and no length,
     * and `audio-playback` forbids inventing one.
     *
     * @param path where the publication's bytes are, as the library recorded it.
     */
    suspend fun of(
        publication: Publication,
        path: String?,
        resolver: ContentResolver,
        playing: NowPlaying?,
    ): List<AudiobookPart> {
        if (!publication.format.isAudio) return emptyList()
        val session = playing?.takeIf { it.publicationId == publication.id }
        if (session != null) {
            return session.parts.map { AudiobookPart(it.title, it.duration.statedMillis) }
        }
        val location = path ?: return emptyList()
        return withContext(Dispatchers.IO) {
            OpenedAudiobook.of(publication, location, resolver)
                ?.sources
                ?.map { AudiobookPart(title = it.title, statedMillis = null) }
                .orEmpty()
        }
    }
}
