package app.storyarc.core.playback

import androidx.media3.common.Player

/**
 * media3's account of who silenced the audio, in the shared table's words.
 *
 * **Why this exists.** `audio-playback` asks for three different outcomes when something
 * takes the audio — resume when the system says it may, never undo a pause the listener
 * made, and end the session outright when the audio is gone for good — and
 * [PlaybackSession] has decided between them since read-aloud's table moved into this
 * module. Read-aloud reaches it through its own `AudioManager.OnAudioFocusChangeListener`.
 *
 * A narrated book has no such listener: media3 requests and handles the focus itself
 * (`setAudioAttributes(…, handleAudioFocus = true)`), so asking for a second focus request
 * beside it would be two owners of one thing. What media3 reports instead is three facts,
 * and the difference between a call and a listener's thumb is in **which** of them moved:
 *
 * | What happened | `isPlaying` | `playWhenReady` | suppression reason |
 * | --- | --- | --- | --- |
 * | Playing | true | true | `NONE` |
 * | The listener paused | false | **false** | `NONE` |
 * | A call took the audio for a moment | false | true | `TRANSIENT_AUDIO_FOCUS_LOSS` |
 * | The audio was taken for good | false | **false**, `AUDIO_FOCUS_LOSS` | `NONE` |
 *
 * `onIsPlayingChanged(false)` alone is every row but the first, which is why reading it as
 * a listener's pause was wrong for three of them.
 *
 * **Read from the player, not remembered from the last callback.** media3 queues
 * `onPlayWhenReadyChanged`, then `onPlaybackSuppressionReasonChanged`, then
 * `onIsPlayingChanged` from one playback-info update; a mapping that remembered the last
 * one it saw would depend on that order, and this one does not.
 */
internal object PlaybackFocus {

    /**
     * Whether a suppression is the audio being taken away from the listener.
     *
     * media3 1.11.0 declares five reasons and they are not all interruptions:
     * `SCRUBBING` is the player's own doing while a listener drags the scrub control, and
     * reading it as a phone call would put the session in the one state that starts
     * playing again by itself the moment the drag ends. The audio-focus and unsuitable-
     * route reasons are genuine: something outside the app silenced it and will give it
     * back.
     */
    fun isInterruption(suppressionReason: Int): Boolean =
        suppressionReason != Player.PLAYBACK_SUPPRESSION_REASON_NONE &&
            suppressionReason != Player.PLAYBACK_SUPPRESSION_REASON_SCRUBBING

    /**
     * Whether media3 has given the audio up rather than waiting for it.
     *
     * Both reasons end the session: a permanent focus loss, and a suppression media3 has
     * carried so long that it stops holding the playback open. `audio-playback` asks for
     * the same thing of both — "audio taken for good ends the session and records the
     * position rather than leaving it paused for ever".
     *
     * **`AUDIO_BECOMING_NOISY` is deliberately not here.** Headphones coming out is a
     * pause, not an ending, and it is the *listener's* pause — see [silenced].
     */
    fun isAudioLostForGood(playWhenReadyReason: Int): Boolean =
        playWhenReadyReason == Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS ||
            playWhenReadyReason == Player.PLAY_WHEN_READY_CHANGE_REASON_SUPPRESSED_TOO_LONG

    /**
     * The session that follows what the player now reports.
     *
     * @param playWhenReady whether the listener still wants audio. media3's own word for
     *   it, and the one signal that separates a pause somebody made from one made *to*
     *   them: a suppression leaves it true.
     */
    fun silenced(
        session: PlaybackSession,
        isPlaying: Boolean,
        playWhenReady: Boolean,
        suppressionReason: Int,
    ): PlaybackSession = when {
        isPlaying -> session.started()
        isInterruption(suppressionReason) -> session.interrupted()
        !playWhenReady -> session.pausedByListener()
        // Wanting audio, not suppressed, and not playing: buffering, or seeking, or the
        // moment before the first frame. None of those is a pause, and saying they were
        // would put the transport's play button up in the middle of a chapter.
        else -> session
    }
}
