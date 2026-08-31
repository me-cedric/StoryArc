package app.storyarc.core.playback

import android.app.PendingIntent
import android.content.Intent
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * What keeps a book playing once every screen has gone, and puts it where the platform
 * expects to find it.
 *
 * `audio-playback` asks that "playback continues and the compact bar carries it", and that
 * the system's own controls "drive the same session". On Android that is not a styling
 * question: a media app without a `MediaSessionService` is frozen the moment the listener
 * leaves it, has no lock-screen transport, no shade carousel, no resumption after process
 * death and no Android Auto. `design.md` is blunt about it — "a player without it is
 * broken, not unpolished".
 *
 * **A `MediaLibraryService`, which is a `MediaSessionService` with a browse tree on top.**
 * The tree is what a car's head unit reads (`automotive_app_desc.xml` in the manifest), and
 * an audiobook player that cannot be driven from a car is missing its best use. Everything
 * a `MediaSessionService` does, this does too.
 *
 * **The notification is media3's own.** `MediaStyle`, built by
 * `DefaultMediaNotificationProvider` because none is installed here, and that absence is
 * deliberate: a hand-rolled notification is how the shade and the lock screen fall out of
 * step, which is exactly what read-aloud's own hand-rolled one risks. What *is* customised
 * is which two buttons sit either side of play/pause — see [seekButtons].
 *
 * iOS needs none of this: `UIBackgroundModes: audio` plus `MPNowPlayingInfoCenter` is the
 * whole of it there, which is one of the two places the platforms genuinely diverge.
 */
@OptIn(UnstableApi::class)
class PlaybackService : MediaLibraryService() {

    private var player: ExoPlayer? = null
    private var session: MediaLibrarySession? = null

    override fun onCreate() {
        super.onCreate()
        val exo = ExoPlayer.Builder(this)
            // **15 seconds back, 30 forward.** A *product decision*, recorded as one:
            // media3's own defaults are 5 s and 15 s, and both are wrong for spoken word
            // in the same direction. Back is the shorter because the reason to skip back
            // is "I missed that sentence" and the reason to skip forward is "I know this
            // part". No guideline says this and none is cited for it.
            .setSeekBackIncrementMs(SEEK_BACK_MS)
            .setSeekForwardIncrementMs(SEEK_FORWARD_MS)
            .setAudioAttributes(SPOKEN_AUDIO, /* handleAudioFocus= */ true)
            // media3 handles the focus loss, and the *meaning* of the pause it makes is
            // `PlaybackSession`'s — see `AudiobookSource.interrupted`. Pausing on a
            // transient loss and resuming afterwards is what this flag buys; refusing to
            // resume a pause the listener made is what the session table adds to it.
            .setHandleAudioBecomingNoisy(true)
            .build()
        player = exo

        session = MediaLibrarySession.Builder(this, exo, LibraryCallback())
            .setSessionActivity(openApp())
            // `setMediaButtonPreferences`, **not** `setCustomLayout`. The latter is
            // deprecated at 1.11.0 and it is the wrong shape besides: a custom layout is
            // an ordered list and every surface — the shade's three slots, the lock
            // screen, a car — has different room. Preferences say which *slot* a button
            // wants, and let each surface place it.
            .setMediaButtonPreferences(seekButtons())
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? =
        session

    /**
     * The listener swiped the app away with nothing playing.
     *
     * media3's own guidance, and the behaviour a listener expects from every other media
     * app: a paused session left behind after the task is gone is a notification for a
     * book nobody is hearing. A *playing* session is left alone, which is the whole point
     * of playback outliving the publication.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        val exo = player
        if (exo == null || !exo.playWhenReady || exo.mediaItemCount == 0) {
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        session?.release()
        session = null
        player?.release()
        player = null
        super.onDestroy()
    }

    /**
     * What sits either side of play/pause, wherever the platform draws a transport.
     *
     * **Seek back and seek forward** — not previous and next, which is media3's own
     * default and is a music player's answer. A listener of a book reaches for fifteen
     * seconds far more often than for a chapter, and the shade's collapsed row has exactly
     * three slots: `SLOT_BACK`, `SLOT_CENTRAL` (play/pause, which media3 places itself)
     * and `SLOT_FORWARD`.
     *
     * `MiniController` was rejected on the app's own surface for the same reason — its
     * default controls are previous / play-pause / next.
     *
     * The icons carry the intervals, because the intervals are a **product decision** and
     * a listener reading the control needs to be told which it is.
     */
    private fun seekButtons(): ImmutableList<CommandButton> = ImmutableList.of(
        CommandButton.Builder(CommandButton.ICON_SKIP_BACK_15)
            .setPlayerCommand(Player.COMMAND_SEEK_BACK)
            .setSlots(CommandButton.SLOT_BACK)
            .setDisplayName(getString(R.string.playback_skip_back))
            .build(),
        CommandButton.Builder(CommandButton.ICON_SKIP_FORWARD_30)
            .setPlayerCommand(Player.COMMAND_SEEK_FORWARD)
            .setSlots(CommandButton.SLOT_FORWARD)
            .setDisplayName(getString(R.string.playback_skip_forward))
            .build(),
    )

    /** Back to the app, which is where the compact bar and the full player are. */
    private fun openApp(): PendingIntent =
        PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName) ?: Intent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /**
     * What a controller — the shade, the lock screen, a car — may ask of this session.
     */
    private inner class LibraryCallback : MediaLibrarySession.Callback {

        /**
         * Declares the two seek commands the collapsed row's outer buttons need.
         *
         * `COMMAND_SEEK_TO_PREVIOUS` and `COMMAND_SEEK_TO_NEXT` are the *chapter* moves and
         * come with the player; `COMMAND_SEEK_BACK` and `COMMAND_SEEK_FORWARD` are the
         * fifteen and thirty seconds. All four are available because the notification
         * carries the seconds and a car's head unit carries the chapters, and a command
         * left undeclared is a button that does nothing.
         */
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
        ): MediaSession.ConnectionResult =
            // The two-argument builder, not the one-argument one: that overload is
            // deprecated at 1.11.0 and it cannot tailor the answer to the controller
            // asking, which is the whole reason a controller is passed to this callback.
            MediaSession.ConnectionResult.AcceptedResultBuilder(session, controller)
                .setAvailablePlayerCommands(
                    MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS.buildUpon()
                        .add(Player.COMMAND_SEEK_BACK)
                        .add(Player.COMMAND_SEEK_FORWARD)
                        .add(Player.COMMAND_SEEK_TO_PREVIOUS)
                        .add(Player.COMMAND_SEEK_TO_NEXT)
                        .build(),
                )
                .setMediaButtonPreferences(seekButtons())
                .build()

        /**
         * What the notification-shade carousel plays when the process has been gone.
         *
         * The one callback that makes resumption work at all: the system asks a service it
         * has just started what the listener was in the middle of, and an app that answers
         * nothing gets no carousel entry. The answer is the position the app recorded —
         * `reading-progress` already stores it, and [resumption] is where the app hands it
         * over, because a service rebuilt from nothing has no database of its own.
         */
        override fun onPlaybackResumption(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            // The three-argument overload; the two-argument one is deprecated at 1.11.0.
            // `isForPlayback` is false when the system only wants something to *draw* in
            // the carousel and true when the listener has pressed play on it. The answer
            // is the same either way — the saved position — because the carousel's row and
            // the audio behind it have to name the same place, and giving the drawing pass
            // a different one is how a listener presses play on "Chapter 4" and gets
            // chapter 1.
            isForPlayback: Boolean,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            val saved = resumption
                ?: return Futures.immediateFailedFuture(
                    UnsupportedOperationException("nothing was playing"),
                )
            return Futures.immediateFuture(
                MediaSession.MediaItemsWithStartPosition(
                    saved.items,
                    saved.startIndex,
                    saved.startPositionMs,
                ),
            )
        }

        // No `onCustomCommand`. Every control this player offers is a *player* command —
        // play, pause, seek, seek-back, seek-forward, next, previous — so there is nothing
        // custom to answer, and media3's own default already refuses one. An override here
        // would be a refusal written twice.
    }

    companion object {
        /**
         * 15 seconds back. A **product decision** — media3's own default is 5 s.
         *
         * @see customLayout
         */
        const val SEEK_BACK_MS: Long = 15_000

        /** 30 seconds forward. A **product decision** — media3's own default is 15 s. */
        const val SEEK_FORWARD_MS: Long = 30_000

        /**
         * Spoken word, not music.
         *
         * `USAGE_MEDIA` with `CONTENT_TYPE_SPEECH` is the closest Android has to iOS's
         * `AVAudioSession.Mode.spokenAudio`, and it is what tells the platform to duck
         * rather than mix when a navigation direction arrives — which for a book is the
         * difference between missing a sentence and hearing it quietly.
         */
        val SPOKEN_AUDIO: AudioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH)
            .build()

        /**
         * What the app last had playing, for the system to resume after process death.
         *
         * A process-wide handoff rather than a database read, because a service the system
         * has just started to answer the carousel has no scope, no dependencies and no
         * time — and because `:core:playback` deliberately does not depend on
         * `:core:persistence`. The app writes it whenever it starts or moves a book; the
         * callback above reads it.
         *
         * Null after a cold start, and that is the honest answer: the app has not run, so
         * nothing here knows what was playing, and the carousel shows nothing rather than
         * something wrong.
         */
        @Volatile
        var resumption: Resumption? = null
    }

    /** Where the system should pick a book up, if the process comes back without the app. */
    data class Resumption(
        val items: List<MediaItem>,
        val startIndex: Int,
        val startPositionMs: Long,
    )
}
