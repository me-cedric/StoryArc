package app.storyarc.core.playback

import android.content.ComponentName
import android.content.Context
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The one session in the app's process, and the one thing every surface observes.
 *
 * An `object`, because a process-wide singleton is the only lifetime longer than every
 * screen, and because `audio-playback` allows exactly one session: "two books speaking at
 * once is never what was meant". `ReadAloudHost` is the same shape for the same reason, and
 * this is where the two will meet — read-aloud has its own engine and its own host today,
 * and the seam that lets it become a second [PlayerSource] is [start].
 *
 * **What it owns and what it does not.** It owns the connection to [PlaybackService] and
 * the [PlaybackCentre] that drives whatever is playing. It does not own the audio: the
 * service does, which is what lets a book carry on when the app's process is trimmed to
 * the service alone.
 */
object PlaybackHost {

    private val _nowPlaying = MutableStateFlow<NowPlaying?>(null)

    /** What every playback surface draws, or null when nothing is playing. */
    val nowPlaying: StateFlow<NowPlaying?> = _nowPlaying.asStateFlow()

    /**
     * Where a position goes when a session gives it up.
     *
     * Set by the app once, at start-up. A lambda rather than a `ProgressStore`, because
     * `:core:playback` decodes audio and has no business knowing that a library keeps a
     * database — and because the same hook is what will let read-aloud's own writer stay
     * where it is.
     */
    var recordPosition: ((publicationId: String, position: PlaybackPosition, parts: List<PlaybackPart>) -> Unit)? = null

    private val centre = PlaybackCentre(
        record = { source, position ->
            recordPosition?.invoke(source.publicationId, position, source.parts)
        },
    ).apply {
        onChange = { _nowPlaying.value = it }
    }

    /** The id of the publication being played, or null. Feeds `SessionHandover.opening`. */
    val playingId: String? get() = centre.playingId

    private var controller: MediaController? = null
    private var current: AudiobookSource? = null

    /**
     * Plays a narrated audiobook, displacing whatever was playing.
     *
     * The controller is built on the first call and kept: connecting is asynchronous — it
     * binds to a service — and doing it per book would put a bind between the listener's
     * press and the first sound.
     */
    fun start(context: Context, book: Audiobook, from: PlaybackPosition? = null, chapterWord: String = "Chapter") {
        withController(context) { player ->
            val source = AudiobookSource(book, player, chapterWord)
            current = source
            source.prepare(from)
            centre.start(source)
            PlaybackService.resumption = PlaybackService.Resumption(
                items = book.sources.map { androidx.media3.common.MediaItem.fromUri(it.uri) },
                startIndex = from?.partIndex ?: 0,
                startPositionMs = from?.offsetMillis ?: 0L,
            )
        }
    }

    /** Pause and play, from wherever the listener reached for it. */
    fun toggle() = centre.toggle()

    /** Ends the session: the listener closed it, or the book ran out of audio. */
    fun stop() {
        centre.stop()
        current = null
    }

    fun seek(to: PlaybackPosition) = centre.seek(to)

    fun setSpeed(speed: PlaybackSpeed) = centre.setSpeed(speed)

    /** Moves to the start of a part, whichever way this publication's parts are laid out. */
    fun seekToPart(index: Int) {
        current?.seekToPart(index)
    }

    /** Skips by the player's own interval, which is a product decision and not media3's. */
    fun skip(forward: Boolean) {
        val playing = _nowPlaying.value ?: return
        val by = if (forward) PlaybackService.SEEK_FORWARD_MS else -PlaybackService.SEEK_BACK_MS
        // Clamped at zero and nowhere else. `audio-playback`: "skipping past the start or
        // the end of a chapter continues into the neighbouring one rather than stopping at
        // the boundary" — for a single file that is free, because a chapter is a mark and
        // not an item; for a folder media3 carries the seek into the next item itself.
        centre.seek(
            PlaybackPosition(
                partIndex = playing.partIndex,
                offsetMillis = (playing.offsetMillis + by).coerceAtLeast(0),
            ),
        )
    }

    private fun withController(context: Context, body: (MediaController) -> Unit) {
        controller?.let { body(it); return }
        val token = SessionToken(
            context.applicationContext,
            ComponentName(context.applicationContext, PlaybackService::class.java),
        )
        val future = MediaController.Builder(context.applicationContext, token).buildAsync()
        future.addListener(
            {
                val built = runCatching { future.get() }.getOrNull() ?: return@addListener
                controller = built
                body(built)
            },
            // The main thread, because everything a `Player` is asked below has to be.
            MoreExecutors.directExecutor(),
        )
    }
}
