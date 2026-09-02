package app.storyarc.core.playback

import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionError
import androidx.media3.session.SessionResult
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

    /**
     * What was playing last, read from disk rather than from a field.
     *
     * The field this used to be is null in exactly the case the resumption callback exists
     * for — a process the system has just created to answer the carousel. See
     * [PlaybackMemory].
     */
    private val memory: PlaybackMemory by lazy { PlaybackMemory.open(this) }

    /**
     * How far the listener asked a skip to go, read from disk for the same reason.
     *
     * Asked again at every press rather than cached, so a change made in the app reaches
     * the shade's own buttons without the service being restarted. `SharedPreferences`
     * keeps the file in memory after the first read, so the cost is a map lookup.
     */
    private val skips: SkipPreferences by lazy { SkipPreferences.open(this) }

    override fun onCreate() {
        super.onCreate()
        val intervals = skips.intervals()
        val exo = ExoPlayer.Builder(this)
            // **15 seconds back, 30 forward by default.** A *product decision*, recorded as
            // one: media3's own defaults are 5 s and 15 s, and both are wrong for spoken
            // word in the same direction. Back is the shorter because the reason to skip
            // back is "I missed that sentence" and the reason to skip forward is "I know
            // this part". No guideline says this and none is cited for it.
            //
            // These are the increments a *generic* seek uses — a car's voice command, an
            // Assistant, a Wear tile — and they clamp to the current item, which for a
            // folder is a boundary stop. The app's own controls and the notification's two
            // outer buttons do not come through here; they come through [skip], which
            // carries across the boundary. Set anyway so the one path this cannot fix at
            // least moves by the right amount.
            .setSeekBackIncrementMs(intervals.millis(SkipDirection.BACK))
            .setSeekForwardIncrementMs(intervals.millis(SkipDirection.FORWARD))
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
    private fun seekButtons(): ImmutableList<CommandButton> {
        val intervals = skips.intervals()
        return ImmutableList.of(
            skipButton(SkipDirection.BACK, intervals, CommandButton.SLOT_BACK),
            skipButton(SkipDirection.FORWARD, intervals, CommandButton.SLOT_FORWARD),
        )
    }

    /**
     * One of those two, carrying its own interval in its glyph and its words.
     *
     * **A session command, not `COMMAND_SEEK_BACK`.** media3 answers a player seek command
     * itself, with `seekBack()` / `seekForward()`, and those clamp to the current item at
     * both ends — so the shade's button would stop at a folder's file boundary while the
     * app's own control carried across it, and `audio-playback` asks for the carry wherever
     * "a listener uses skip back or skip forward". A session command arrives at
     * [LibraryCallback.onCustomCommand] instead, where the same [PlaybackTimeline] the app
     * uses decides where it lands.
     */
    private fun skipButton(
        direction: SkipDirection,
        intervals: SkipIntervals,
        slot: Int,
    ): CommandButton {
        val seconds = intervals.seconds(direction)
        // A plural, not a string. The interval is a number the listener chose, and a
        // language that inflects around it has to be able to.
        val label = when (direction) {
            SkipDirection.BACK ->
                resources.getQuantityString(R.plurals.playback_skip_back, seconds, seconds)
            SkipDirection.FORWARD ->
                resources.getQuantityString(R.plurals.playback_skip_forward, seconds, seconds)
        }
        val action = when (direction) {
            SkipDirection.BACK -> COMMAND_SKIP_BACK
            SkipDirection.FORWARD -> COMMAND_SKIP_FORWARD
        }
        return CommandButton.Builder(skipIcon(direction, seconds))
            .setSessionCommand(SessionCommand(action, Bundle.EMPTY))
            .setSlots(slot)
            .setDisplayName(label)
            .build()
    }

    /**
     * Where a skip from a controller lands.
     *
     * The service's own copy of the app's rule, and deliberately the same function behind
     * it: a folder is a playlist of items, so the offset goes out to whole-book time and
     * back, and a single file is one item whose window duration is the whole book — which
     * makes the same call clamp it to its two ends and nothing else. The chapter marks
     * inside it are not the service's business; they are inside one continuous item.
     */
    private fun skip(direction: SkipDirection) {
        val exo = player ?: return
        val timeline = exo.currentTimeline
        if (timeline.isEmpty) return
        // Titles are the app's, and a skip does not need one. What it needs is the lengths.
        val parts = timeline.partDurations().map { PlaybackPart(title = "", duration = it) }
        val interval = skips.intervals().millis(direction)
        val by = if (direction == SkipDirection.BACK) -interval else interval
        val from = PlaybackPosition(
            partIndex = exo.currentMediaItemIndex,
            offsetMillis = exo.currentPosition.coerceAtLeast(0),
        )
        val landed = PlaybackTimeline.skip(parts, from, by) ?: return
        exo.seekTo(landed.partIndex, landed.offsetMillis)
    }

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
                // The three the buttons above and the app need. A session command left
                // undeclared is a button whose press is refused, which looks exactly like a
                // button that does nothing.
                .setAvailableSessionCommands(
                    MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS.buildUpon()
                        .add(SessionCommand(COMMAND_SKIP_BACK, Bundle.EMPTY))
                        .add(SessionCommand(COMMAND_SKIP_FORWARD, Bundle.EMPTY))
                        .add(SessionCommand(COMMAND_REFRESH_BUTTONS, Bundle.EMPTY))
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
            // From the app while it is running, and from disk when it is not — which is
            // the whole case this callback is for. A process-wide field alone answered
            // null every time the system started this service on its own.
            val saved = resumption ?: memory.last()?.let(::resumptionOf)
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

        /**
         * The top of the tree a head unit browses.
         *
         * Unimplemented, this answered `RESULT_ERROR_NOT_SUPPORTED` — so a car that had
         * found the app in its launcher could drive what was already playing and could not
         * start anything. The root is a browsable folder of audiobooks, which is what tells
         * a head unit to draw a list rather than a grid of album art.
         */
        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> =
            Futures.immediateFuture(LibraryResult.ofItem(root(), params))

        /**
         * What is under the root: the book the listener is in the middle of.
         *
         * **One node, and its limits are worth stating.** A car's best use of a book player
         * is carrying on with the book, and that is what this offers. It is *not* the
         * library: `:core:playback` has no library in it, and a browse tree built from a
         * copy of one would go stale the moment a download finished. Offering the whole
         * shelf from a car needs the app to publish it, and that is not built.
         *
         * An empty list rather than an error where nothing has been played: a car showing
         * an empty list is a car saying there is nothing to continue, which is true.
         */
        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            if (parentId != ROOT_ID) {
                return Futures.immediateFuture(LibraryResult.ofItemList(ImmutableList.of(), params))
            }
            val last = memory.last()
            val children = last?.let { ImmutableList.of(browseItem(it)) } ?: ImmutableList.of()
            return Futures.immediateFuture(LibraryResult.ofItemList(children, params))
        }

        /** One item by id, which is what a head unit asks for before it plays one. */
        override fun onGetItem(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            mediaId: String,
        ): ListenableFuture<LibraryResult<MediaItem>> {
            val last = memory.last()?.takeIf { it.id == mediaId }
                ?: return Futures.immediateFuture(LibraryResult.ofError<MediaItem>(SessionError.ERROR_BAD_VALUE))
            return Futures.immediateFuture(LibraryResult.ofItem(browseItem(last), null))
        }

        /**
         * A browsed item, turned into audio.
         *
         * The id a car sends back is the publication's, and what it means is "carry on with
         * this" — so the parts and the offset come from the same memory the row was drawn
         * from, and pressing play in a car lands where the listener left off rather than at
         * the start of chapter one.
         */
        override fun onSetMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
            startIndex: Int,
            startPositionMs: Long,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            val asked = mediaItems.singleOrNull()?.mediaId
            val last = memory.last()?.takeIf { it.id == asked }
                ?: return super.onSetMediaItems(
                    mediaSession,
                    controller,
                    mediaItems,
                    startIndex,
                    startPositionMs,
                )
            return Futures.immediateFuture(resumptionOf(last).let {
                MediaSession.MediaItemsWithStartPosition(it.items, it.startIndex, it.startPositionMs)
            })
        }

        /**
         * The two skips, and the nudge that relabels their buttons.
         *
         * **This used to say there was nothing custom to answer**, because both skips were
         * `COMMAND_SEEK_BACK` and `COMMAND_SEEK_FORWARD` and media3 answered them itself.
         * What it answered them with is `BasePlayer.seekToOffset`, which clamps to the
         * current item — the boundary stop `audio-playback` forbids — so the shade's own
         * buttons disagreed with the app's controls for a folder. They are session commands
         * now, and this is where they land.
         *
         * The player commands are still declared in [onConnect]: a car's voice command and
         * an Assistant send those, they are not ours to redirect, and a generic seek of the
         * right length that stops at a file boundary is better than none.
         */
        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> = when (customCommand.customAction) {
            COMMAND_SKIP_BACK -> {
                skip(SkipDirection.BACK)
                Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
            COMMAND_SKIP_FORWARD -> {
                skip(SkipDirection.FORWARD)
                Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
            // The listener changed the interval while the shade was showing the old number.
            // The buttons carry it in their glyph and their words, and they are only sent
            // when a controller connects — so the app asks for them to be sent again.
            COMMAND_REFRESH_BUTTONS -> {
                this@PlaybackService.session?.setMediaButtonPreferences(seekButtons())
                Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
            else -> Futures.immediateFuture(SessionResult(SessionError.ERROR_NOT_SUPPORTED))
        }
    }

    /** The one browsable node, so a head unit has a list to draw. */
    private fun root(): MediaItem = MediaItem.Builder()
        .setMediaId(ROOT_ID)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setIsBrowsable(true)
                .setIsPlayable(false)
                .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_AUDIO_BOOKS)
                .setTitle(getString(R.string.playback_browse_root))
                .build(),
        )
        .build()

    /**
     * The row a car draws for the book being listened to.
     *
     * Playable and not browsable: a car that expanded it would be asking for a chapter list
     * this tree does not carry, and choosing a chapter from a moving vehicle is not the
     * gesture — carrying on is.
     */
    private fun browseItem(book: PlayedBook): MediaItem = MediaItem.Builder()
        .setMediaId(book.id)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setIsBrowsable(false)
                .setIsPlayable(true)
                .setMediaType(MediaMetadata.MEDIA_TYPE_AUDIO_BOOK)
                .setTitle(book.title)
                .setSubtitle(book.partTitle)
                .setArtist(book.author)
                .setArtworkUri(book.artworkUri?.let(android.net.Uri::parse))
                .build(),
        )
        .build()

    /**
     * What the system needs to put a remembered book back on the air.
     *
     * [PlaybackResumption] rather than a method here, so the mapping can be asserted without
     * a service — see its own note on which half of resumption a host test can reach.
     */
    private fun resumptionOf(book: PlayedBook): Resumption = PlaybackResumption.of(book)

    companion object {
        /** The id of the one browsable node. Stable, because a car caches it. */
        const val ROOT_ID: String = "storyarc:root"

        /**
         * The two skips, as session commands rather than player ones.
         *
         * See [LibraryCallback.onCustomCommand]: media3 answers a player seek by clamping to
         * the current item, and this player has to cross a boundary. How far they move is
         * [SkipPreferences]'s and the defaults are `design.md`'s — 15 back, 30 forward.
         */
        const val COMMAND_SKIP_BACK: String = "app.storyarc.playback.SKIP_BACK"
        const val COMMAND_SKIP_FORWARD: String = "app.storyarc.playback.SKIP_FORWARD"

        /** Send the button preferences again, because their interval changed. */
        const val COMMAND_REFRESH_BUTTONS: String = "app.storyarc.playback.REFRESH_BUTTONS"

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
