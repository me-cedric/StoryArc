package app.storyarc

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.PlaybackPreferences
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.playback.Audiobook
import app.storyarc.core.playback.PlaybackHost
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackPosition
import app.storyarc.core.playback.PlaybackSpeed
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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

    /** Where the player's own picture of a book is written for the session to load. */
    private const val ARTWORK_DIR = "player-artwork"

    /**
     * A scope as long as the process, not as long as a screen.
     *
     * An activity's `lifecycleScope` ends when the activity does, and the whole point of
     * this player is that the audio outlives every screen — so a writer tied to one would
     * stop writing at exactly the moment a listener has put the phone in their pocket, and
     * would drop the final position when the book ended.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val _following = MutableStateFlow<Publication?>(null)

    /**
     * The publication being played, as the library knows it — or null.
     *
     * What the full player draws its artwork and its format from. `PlaybackHost.nowPlaying`
     * carries an id and a title and nothing more, because `:core:playback` has no business
     * knowing what a `Publication` is; this is the app's half of the answer. Set when a book
     * is started here, and **cleared when the host lets the session go** — the book ran out,
     * the listener stopped it, or another one displaced it — so a second book cannot start
     * under the first's cover. A book the system put back on the air after the process died
     * was started by nothing here, and is answered with null rather than with whatever played
     * last.
     */
    val following: StateFlow<Publication?> = _following.asStateFlow()

    /** Where a chosen speed goes, and where the next book's comes from. */
    private var preferences: PlaybackPreferences? = null

    private var ticker: Job? = null

    /** Watches the host for the moment it lets this publication's session go. */
    private var watcher: Job? = null

    /**
     * Starts a book, from where the listener left it.
     *
     * The store is read before the audio is prepared, because a seek after the first sound
     * is a listener hearing four seconds of the wrong chapter.
     *
     * @param from where to start, when the listener chose a chapter rather than resuming.
     *   Null means the saved place, which is what tapping the cover means. The saved place is
     *   read and not written either way — choosing a chapter moves the audio, and the writer
     *   below records where it goes on its own tick.
     */
    fun play(
        context: Context,
        publication: Publication,
        book: Audiobook,
        store: ProgressStore,
        speeds: PlaybackPreferences,
        chapterWord: String,
        from: PlaybackPosition? = null,
    ) {
        follow(publication, store)
        preferences = speeds
        scope.launch {
            val record = store.progress(publication.identity)
            PlaybackHost.start(
                context = context,
                book = book,
                from = from
                    ?: ListenedPosition.resume(record?.position, record?.isFinished == true),
                speed = PlaybackSpeed.of(speeds.speed(publication.id, publication.series)),
                chapterWord = chapterWord,
            )
        }
    }

    /**
     * Changes the speed, and remembers it.
     *
     * `audio-playback`: the value "is remembered for that publication and offered as the
     * default for others in the same series". Written as it is chosen rather than when the
     * book ends, because a listener who adjusts the speed and then loses the process would
     * otherwise be asked the same question again.
     */
    fun setSpeed(speed: PlaybackSpeed) {
        PlaybackHost.setSpeed(speed)
        val publication = _following.value ?: return
        preferences?.rememberSpeed(publication.id, publication.series, speed.rate)
    }

    /**
     * The picture the player drew, handed to the system's own controls.
     *
     * `audio-playback`: the lock screen and the shade are "given that same artwork rather than
     * a second one". Written under the cache directory and handed over as a file, because
     * media3 loads a session's artwork from a URI — a `file://` one goes through the same data
     * source that plays the book — and a bitmap across the binder is a copy of every pixel on
     * every refresh. The cache directory rather than files, because it is a picture the player
     * can draw again.
     *
     * Only for the publication still being followed, checked before the write and again after
     * it: a listener who started a second book while the first's picture was still being
     * written must not get the first's cover on the second's lock screen.
     */
    fun artwork(context: Context, publicationId: String, picture: Bitmap) {
        if (_following.value?.id != publicationId) return
        scope.launch {
            val file = withContext(Dispatchers.IO) {
                runCatching {
                    val directory = File(context.cacheDir, ARTWORK_DIR).apply { mkdirs() }
                    val name = publicationId.hashCode().toUInt().toString(36)
                    File(directory, "$name.png").also { file ->
                        file.outputStream().use { picture.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    }
                }.getOrNull()
            } ?: return@launch
            if (_following.value?.id != publicationId) return@launch
            PlaybackHost.setArtwork(publicationId, Uri.fromFile(file))
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
        _following.value = publication
        PlaybackHost.recordPosition = { id, position, parts ->
            val known = _following.value
            // A book started before this process was, resumed by the notification-shade
            // carousel, reaches here with an id nothing in the app has seen. Writing the
            // position against the wrong publication is worse than not writing it, so it
            // is dropped — and that is the honest state of resumption after process death.
            if (known != null && known.id == id) {
                scope.launch { write(store, known, position, parts) }
            }
        }

        watcher?.cancel()
        watcher = scope.launch {
            // The host publishes null between `play` and the first sound as well as after the
            // last one, so a null before this book has been seen playing is the gap and not
            // the ending. Seen once, the next null — or another book's id — is the session
            // let go, whichever of the three endings let it go: `PlaybackCentre` routes all of
            // them through one teardown.
            var seen = false
            PlaybackHost.nowPlaying.collect { playing ->
                when {
                    playing?.publicationId == publication.id -> seen = true
                    seen && _following.value === publication -> _following.value = null
                }
            }
        }

        ticker?.cancel()
        ticker = scope.launch {
            while (isActive) {
                delay(TICK_MILLIS)
                val playing = PlaybackHost.nowPlaying.value ?: continue
                val known = _following.value ?: continue
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
