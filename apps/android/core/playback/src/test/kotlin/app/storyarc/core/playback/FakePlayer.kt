package app.storyarc.core.playback

import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import java.lang.reflect.Proxy

/**
 * A `Player` that answers nothing.
 *
 * `Player` has more than a hundred members and [AudiobookSource] touches a dozen, so the
 * fake below implements the dozen and delegates the rest here. A reflective proxy rather
 * than a hand-written stub because a hand-written one is a hundred lines that will need
 * editing every time media3 adds a method, and none of them would ever be called.
 */
private val UNUSED: Player = Proxy.newProxyInstance(
    Player::class.java.classLoader,
    arrayOf(Player::class.java),
) { _, method, _ ->
    when (method.returnType) {
        Boolean::class.javaPrimitiveType -> false
        Int::class.javaPrimitiveType -> 0
        Long::class.javaPrimitiveType -> 0L
        Float::class.javaPrimitiveType -> 0f
        else -> null
    }
} as Player

/**
 * media3's own signals, without media3.
 *
 * **What this fake is and is not.** It is not a decoder and it does not model ExoPlayer;
 * it reproduces the four facts [AudiobookSource] reads — `isPlaying`, `playWhenReady`,
 * `playbackSuppressionReason` and the position — and the order media3 reports a change to
 * them in. That order is `ExoPlayerImpl`'s: `onPlayWhenReadyChanged`, then
 * `onPlaybackSuppressionReasonChanged`, then `onIsPlayingChanged`, all queued from one
 * playback-info update and flushed in that order.
 *
 * So a test built on it pins **our** mapping from those signals onto the shared session
 * table. That a real focus loss produces those signals is media3's contract rather than
 * this suite's finding, and hearing it happen on a device is a separate exercise.
 */
internal class FakePlayer : Player by UNUSED {

    private val listeners = mutableListOf<Player.Listener>()

    private var playing = false
    private var wantsToPlay = false
    private var suppression = Player.PLAYBACK_SUPPRESSION_REASON_NONE
    private var items = emptyList<MediaItem>()
    private var positionMs = 0L
    private var itemIndex = 0
    private var timeline: Timeline = Timeline.EMPTY
    private var durationMs = 0L

    var isStopped = false
        private set

    override fun addListener(listener: Player.Listener) {
        listeners += listener
    }

    override fun removeListener(listener: Player.Listener) {
        listeners -= listener
    }

    override fun setMediaItems(mediaItems: MutableList<MediaItem>) {
        items = mediaItems.toList()
    }

    override fun getCurrentMediaItem(): MediaItem? = items.getOrNull(itemIndex)

    override fun getCurrentMediaItemIndex(): Int = itemIndex

    override fun getCurrentPosition(): Long = positionMs

    override fun getDuration(): Long = durationMs

    override fun getCurrentTimeline(): Timeline = timeline

    override fun getPlaybackParameters(): PlaybackParameters = PlaybackParameters.DEFAULT

    override fun isPlaying(): Boolean = playing

    override fun getPlayWhenReady(): Boolean = wantsToPlay

    override fun getPlaybackSuppressionReason(): Int = suppression

    override fun prepare() = Unit

    override fun play() {
        if (wantsToPlay && playing) return
        wantsToPlay = true
        change(playWhenReadyReason = Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST) {
            playing = suppression == Player.PLAYBACK_SUPPRESSION_REASON_NONE
        }
    }

    override fun pause() {
        if (!wantsToPlay) return
        change(playWhenReadyReason = Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST) {
            wantsToPlay = false
            playing = false
        }
    }

    override fun stop() {
        isStopped = true
        change { playing = false; wantsToPlay = false }
    }

    override fun clearMediaItems() {
        items = emptyList()
        positionMs = 0
        itemIndex = 0
    }

    override fun seekTo(positionMs: Long) {
        this.positionMs = positionMs
    }

    override fun seekTo(mediaItemIndex: Int, positionMs: Long) {
        itemIndex = mediaItemIndex
        this.positionMs = positionMs
    }

    override fun setPlaybackSpeed(speed: Float) = Unit

    /** The listener is somewhere in the book. Sets the position a stop would record. */
    fun reach(millis: Long) {
        positionMs = millis
    }

    /** Which part of a folder is playing, without a transition having been reported. */
    fun reachPart(index: Int, millis: Long) {
        itemIndex = index
        positionMs = millis
    }

    /**
     * The decoder has read the playlist and knows how long each file is.
     *
     * media3 reports this as a timeline change, and the durations are on the *windows* —
     * there is no per-item duration API anywhere else, which is why the source reads a
     * `Timeline` at all. A negative millis here stands for `C.TIME_UNSET`: a file the
     * decoder has not measured.
     */
    fun measure(vararg durationsMs: Long) {
        timeline = WindowDurations(durationsMs.toList())
        listeners.toList()
            .forEach { it.onTimelineChanged(timeline, Player.TIMELINE_CHANGE_REASON_SOURCE_UPDATE) }
    }

    /** How long the one file of a single-file book is, as the decoder eventually says. */
    fun measureFile(millis: Long) {
        durationMs = millis
    }

    /**
     * A call, a navigation direction, another app: the audio is taken for a moment.
     *
     * media3 owns the focus (`setAudioAttributes(…, handleAudioFocus = true)`), and what it
     * does with a transient loss is *suppress*: the listener still wants audio, so
     * `playWhenReady` stays true and only `isPlaying` goes false.
     */
    fun suppress(reason: Int = Player.PLAYBACK_SUPPRESSION_REASON_TRANSIENT_AUDIO_FOCUS_LOSS) {
        change { suppression = reason; playing = false }
    }

    /** The audio comes back, and media3 starts again by itself if the listener still wants it. */
    fun unsuppress() {
        change {
            suppression = Player.PLAYBACK_SUPPRESSION_REASON_NONE
            playing = wantsToPlay
        }
    }

    /**
     * The audio is taken and kept.
     *
     * media3 answers a permanent focus loss by clearing `playWhenReady` with its own
     * reason, which is the one signal that separates it from the listener pressing pause.
     */
    fun loseAudioForGood(reason: Int = Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS) {
        change(playWhenReadyReason = reason) {
            wantsToPlay = false
            playing = false
            suppression = Player.PLAYBACK_SUPPRESSION_REASON_NONE
        }
    }

    /** Applies a change and reports it the way media3 reports one. */
    private fun change(playWhenReadyReason: Int? = null, body: () -> Unit) {
        val wasPlaying = playing
        val wasSuppressed = suppression
        val wanted = wantsToPlay
        body()
        // The order is `ExoPlayerImpl`'s, and it is what makes reading the *player* rather
        // than remembering the last callback unnecessary — but the source reads the player
        // anyway, so a reversed order would change nothing. See `PlaybackFocus`.
        val snapshot = listeners.toList()
        if (wanted != wantsToPlay && playWhenReadyReason != null) {
            snapshot.forEach { it.onPlayWhenReadyChanged(wantsToPlay, playWhenReadyReason) }
        }
        if (wasSuppressed != suppression) {
            snapshot.forEach { it.onPlaybackSuppressionReasonChanged(suppression) }
        }
        if (wasPlaying != playing) {
            snapshot.forEach { it.onIsPlayingChanged(playing) }
        }
    }
}

/**
 * A timeline that carries nothing but a duration per window.
 *
 * Which is all [AudiobookSource] reads out of one. Hand-written rather than media3's own
 * `FakeTimeline`: that lives in `media3-test-utils`, is `@UnstableApi`, and would put a
 * whole artifact on this module's test classpath to supply six overrides. The duration is
 * set on the window's public field instead of through the fourteen-argument `set`, because
 * every other argument is a value nothing here asks about.
 */
private class WindowDurations(private val durationsMs: List<Long>) : Timeline() {

    override fun getWindowCount(): Int = durationsMs.size

    override fun getWindow(
        windowIndex: Int,
        window: Window,
        defaultPositionProjectionUs: Long,
    ): Window {
        val millis = durationsMs[windowIndex]
        window.uid = windowIndex
        window.durationUs = if (millis < 0) C.TIME_UNSET else millis * 1_000
        return window
    }

    override fun getPeriodCount(): Int = durationsMs.size

    override fun getPeriod(periodIndex: Int, period: Period, setIds: Boolean): Period = period

    override fun getIndexOfPeriod(uid: Any): Int = uid as? Int ?: C.INDEX_UNSET

    override fun getUidOfPeriod(periodIndex: Int): Any = periodIndex
}
