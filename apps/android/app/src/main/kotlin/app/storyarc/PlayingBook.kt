package app.storyarc

import android.content.Context
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.playback.Audiobook
import app.storyarc.core.playback.PlaybackHost
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackPosition
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Keeping a listener's place, so closing an audiobook does not lose it.
 *
 * `PlaybackHost` publishes a position and offers a hook for writing one down; until now
 * nothing set the hook, so a book closed at chapter four opened at chapter one. This is
 * what fills it in, and the one place a `ProgressStore` and a `PlaybackHost` meet.
 *
 * **Written while playing, not only on leaving.** ADR-0006 makes the local store
 * authoritative and `ReaderViewModel` writes a page on every turn for the same reason: an
 * app killed in the background is the normal way a phone closes one, and a position that
 * only travelled on a clean exit would be the walk home lost. A book has no page turns to
 * hang that on, so it is a tick — the same fifteen seconds `ReadingProgress` describes its
 * own `updatedAtEpochMillis` as moving on.
 */
internal object PlayingBook {

    /** How often a playing book writes down where it has reached. */
    private const val TICK_MILLIS = 15_000L

    /**
     * A scope as long as the process, not as long as a screen.
     *
     * An activity's `lifecycleScope` ends when the activity does, and the whole point of
     * this player is that the audio outlives every screen — so a writer tied to one would
     * stop writing at exactly the moment a listener has put the phone in their pocket, and
     * would drop the final position when the book ended.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** The publication the hook below is writing for. */
    private var following: Publication? = null

    private var ticker: Job? = null

    /**
     * Starts a book, from where the listener left it.
     *
     * The store is read before the audio is prepared, because a seek after the first sound
     * is a listener hearing four seconds of the wrong chapter.
     */
    fun play(
        context: Context,
        publication: Publication,
        book: Audiobook,
        store: ProgressStore,
        chapterWord: String,
    ) {
        follow(publication, store)
        scope.launch {
            val record = store.progress(publication.identity)
            PlaybackHost.start(
                context = context,
                book = book,
                from = ListenedPosition.resume(record?.position, record?.isFinished == true),
                chapterWord = chapterWord,
            )
        }
    }

    /**
     * Points the host's writer at this publication, and starts the tick.
     *
     * The hook is process-wide and takes a publication *id*, because `:core:playback` has
     * no business knowing what a `PublicationIdentity` is. Resolving the id back to one is
     * the app's job, and it is done by remembering the publication that was started rather
     * than by picking the id apart — a stable id is a key, not a serialisation.
     */
    private fun follow(publication: Publication, store: ProgressStore) {
        following = publication
        PlaybackHost.recordPosition = { id, position, parts ->
            val known = following
            // A book started before this process was, resumed by the notification-shade
            // carousel, reaches here with an id nothing in the app has seen. Writing the
            // position against the wrong publication is worse than not writing it, so it
            // is dropped — and that is the honest state of resumption after process death.
            if (known != null && known.id == id) {
                scope.launch { write(store, known, position, parts) }
            }
        }

        ticker?.cancel()
        ticker = scope.launch {
            while (isActive) {
                delay(TICK_MILLIS)
                val playing = PlaybackHost.nowPlaying.value ?: continue
                val known = following ?: continue
                if (!playing.isPlaying || playing.publicationId != known.id) continue
                write(
                    store,
                    known,
                    PlaybackPosition(playing.partIndex, playing.offsetMillis),
                    playing.parts,
                )
            }
        }
    }

    private suspend fun write(
        store: ProgressStore,
        publication: Publication,
        position: PlaybackPosition,
        parts: List<PlaybackPart>,
    ) {
        store.save(
            ReadingProgress(
                identity = publication.identity,
                position = ListenedPosition.of(position, parts),
                // `reading-progress`: finishing by listening is marked by the same rule
                // that marks a comic finished on its last page. Finished is sticky in the
                // store, so a listener who plays on past the end does not unmark it.
                isFinished = ListenedPosition.isFinished(position, parts),
                updatedAtEpochMillis = System.currentTimeMillis(),
            ),
        )
    }
}
