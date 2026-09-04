package app.storyarc.core.playback

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.metadata.Chapter

/**
 * A narrated audiobook, played by media3.
 *
 * One of [PlayerSource]'s two implementations, and the one with a decoder behind it. What
 * it adds over the interface is entirely mapping: media3 speaks in items, windows and
 * metadata entries, and the surfaces speak in parts, positions and durations.
 *
 * **The player is a `Player`, not an `ExoPlayer`**, and that is the whole architecture in
 * one type. `PlaybackService` owns the decoder because media3's session wraps one and the
 * notification is drawn from it; the app holds a `MediaController`, which is also a
 * `Player`, and drives the same audio across the process boundary. A field typed
 * `ExoPlayer` would have made this class unusable from the app and the service the only
 * place a book could be started.
 *
 * There is no `release` here either: ending a session detaches this, and the player outlives
 * it to carry the next book.
 */
class AudiobookSource(
    private val book: Audiobook,
    private val player: Player,
    /** The reader's own word for a chapter, for the marks a container left untitled. */
    private val chapterWord: String = "Chapter",
) : PlayerSource {

    override val publicationId: String get() = book.id
    override val title: String get() = book.title
    override val skippedPartCount: Int get() = book.skippedPartCount

    override var onChange: (() -> Unit)? = null

    override var onInterruptionEnd: ((mayResume: Boolean) -> Unit)? = null

    /**
     * The parts, which for a single file are not known until the decoder has read it.
     *
     * Starts as one part standing in for the whole — `publication-formats`' answer for an
     * unchaptered audiobook, and the honest answer for a chaptered one nobody has opened
     * yet. Replaced once the container's marks arrive, and [onChange] says so.
     */
    override var parts: List<PlaybackPart> = initialParts()
        private set

    /** Where each part starts, for [PartLayout.MARKS]. Empty for a folder. */
    private var offsets: List<Long> = emptyList()

    override val position: PlaybackPosition
        get() = when (book.layout) {
            PartLayout.FILES -> PlaybackPosition(
                partIndex = player.currentMediaItemIndex,
                offsetMillis = player.currentPosition.coerceAtLeast(0),
            )
            // One item, so the part is wherever the position falls between the marks — and
            // the offset stays the offset into the *file*, because that is what a seek
            // takes and what a saved position has to survive a re-download as.
            PartLayout.MARKS -> {
                val at = player.currentPosition.coerceAtLeast(0)
                PlaybackPosition(AudiobookChapters.partAt(offsets, at), at)
            }
        }

    override var session: PlaybackSession = PlaybackSession()
        private set

    override val speed: PlaybackSpeed get() = PlaybackSpeed.of(player.playbackParameters.speed.toDouble())

    /**
     * Reports what the decoder did, so a listener's own pause is never confused with one
     * media3 made.
     *
     * **This used to read every silence as the listener's**, and that was the defect: media3
     * owns the audio focus here, and it reports a call taking the audio as the same
     * `onIsPlayingChanged(false)` a thumb on the notification produces. So a book paused by
     * a phone call was recorded as a book the listener had paused, and the rule
     * `audio-playback` states twice — "a pause the listener made is never undone this way" —
     * had nothing to enforce it on the narrated path; worse, a focus loss for good left the
     * session paused for ever with no position written, which the same requirement forbids
     * by name. Read-aloud had connected all of this through its own focus listener.
     *
     * What separates the cases is in [PlaybackFocus], read from the player rather than
     * remembered, so the order media3 delivers these three callbacks in cannot change the
     * answer.
     */
    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) = report()

        /**
         * The listener stopped wanting audio — or the platform stopped offering it.
         *
         * The reason is the whole content of this callback: media3 names its own when it
         * gives the audio up, and that is the one signal a listener's pause does not carry.
         */
        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            if (!playWhenReady && PlaybackFocus.isAudioLostForGood(reason)) {
                // Ends the session and writes the position, through the shared table. Not
                // done here: the position has to be recorded before anything is stopped,
                // and the centre is what owns that order.
                onInterruptionEnd?.invoke(false)
                return
            }
            report()
        }

        /**
         * Something took the audio for a moment, or gave it back.
         *
         * media3 suppresses rather than pausing for a transient focus loss, which is what
         * keeps `playWhenReady` true through a phone call and is exactly the distinction
         * the session table needs.
         */
        override fun onPlaybackSuppressionReasonChanged(reason: Int) {
            when {
                PlaybackFocus.isInterruption(reason) -> report()
                // Given back, and the listener still wants it. Whether that means play
                // again is the session's decision, never this callback's.
                player.playWhenReady -> onInterruptionEnd?.invoke(true)
                // The suppression lifted because the *listener* paused during it — media3
                // gives the focus up at that point. Nothing here starts a book somebody
                // deliberately silenced.
                else -> report()
            }
        }

        override fun onPlaybackStateChanged(state: Int) {
            // The book ran out of audio. `audio-playback` wants the same thing of both
            // sources at the end — the controls go away — and an idle session is how the
            // centre is told.
            if (state == Player.STATE_ENDED) {
                session = session.stopped()
            }
            onChange?.invoke()
        }

        override fun onMediaItemTransition(item: MediaItem?, reason: Int) {
            onChange?.invoke()
        }

        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int,
        ) {
            onChange?.invoke()
        }

        override fun onTracksChanged(tracks: Tracks) {
            adoptChapters(tracks)
        }

        /**
         * The decoder has read the playlist and knows how long each file is.
         *
         * Which is the only place those lengths come from — see [adoptDurations].
         */
        override fun onTimelineChanged(timeline: Timeline, reason: Int) {
            adoptDurations(timeline)
        }
    }

    /** Asks the player what it is doing now, and tells the table what that means. */
    private fun report() {
        session = PlaybackFocus.silenced(
            session = session,
            isPlaying = player.isPlaying,
            playWhenReady = player.playWhenReady,
            suppressionReason = player.playbackSuppressionReason,
        )
        onChange?.invoke()
    }

    /**
     * The listener asked for audio.
     *
     * **Started before the player is asked, not after it answers**, and the order is the
     * whole of the Android player's biggest defect. [PlaybackCentre.start] attaches its
     * listener and *then* calls this; a real player answers inside the call below — a
     * `MediaController` masks the change and reports it before the request has crossed to
     * the service — with `playWhenReady` true and `isPlaying` still false, because nothing
     * has buffered. [PlaybackFocus.silenced] rightly reads that as neither a pause nor a
     * start and leaves the session alone, so with the assignment underneath it the session
     * was still `IDLE` when the callback reached [PlaybackCentre.publish] — which reads an
     * inactive session as *the book ran out*. The centre dropped the source it had just
     * started, published null, and never heard from it again, while the controller had
     * already told the service to play.
     *
     * That is the sweep's §3: audio playing, `PlayerFinishedScreen` on top of it, no
     * compact bar. Pinned by `PlayerStartTest`.
     */
    override fun play() {
        session = session.started()
        if (player.currentMediaItem == null) prepare()
        player.play()
        onChange?.invoke()
    }

    override fun pause() {
        player.pause()
        session = session.pausedByListener()
        onChange?.invoke()
    }

    override fun stop() {
        player.removeListener(listener)
        player.stop()
        player.clearMediaItems()
        session = session.stopped()
        onChange?.invoke()
    }

    override fun seek(to: PlaybackPosition) {
        when (book.layout) {
            PartLayout.FILES -> player.seekTo(to.partIndex, to.offsetMillis)
            PartLayout.MARKS -> player.seekTo(to.offsetMillis)
        }
        onChange?.invoke()
    }

    /**
     * Moves by an interval, and crosses a part boundary rather than stopping at it.
     *
     * **The two layouts get there differently, and only one needs arithmetic.** A single
     * file's offsets are file-wide, so a mark is a number the position passes and nothing
     * more; what has to be honoured there is the file's own two ends. A folder's offsets are
     * per item, so the interface's default converts to whole-book time and back — which is
     * why a folder's parts have to know their lengths, and [adoptDurations] is where they
     * learn them.
     *
     * Neither case is media3's `seekBack()` / `seekForward()`. Those clamp to the current
     * item at both ends — `BasePlayer.seekToOffset`, read out of the 1.11.0 bytecode — which
     * is the boundary stop `audio-playback` forbids.
     */
    override fun skip(direction: SkipDirection, byMillis: Long) {
        val by = if (direction == SkipDirection.BACK) -byMillis else byMillis
        when (book.layout) {
            PartLayout.FILES -> super.skip(direction, byMillis)
            PartLayout.MARKS -> {
                val reached = player.currentPosition.coerceAtLeast(0)
                val total = player.duration.takeIf { it != C.TIME_UNSET && it > 0 }
                val target = (reached + by).coerceAtLeast(0).let { at ->
                    if (total == null) at else at.coerceAtMost(total)
                }
                seek(PlaybackPosition(AudiobookChapters.partAt(offsets, target), target))
            }
        }
    }

    /** Moves to the start of a part, whichever way this publication's parts are laid out. */
    fun seekToPart(index: Int) {
        when (book.layout) {
            PartLayout.FILES -> player.seekTo(index, 0)
            PartLayout.MARKS -> player.seekTo(offsets.getOrElse(index) { 0L })
        }
        onChange?.invoke()
    }

    override fun setSpeed(speed: PlaybackSpeed) {
        // Pitch is left where it is. media3 keeps the pitch when only the speed moves,
        // which is what a spoken-word listener wants — `audio-playback` asks for speed
        // "without changing pitch", and setting both would be the way to break it.
        player.setPlaybackSpeed(speed.rate.toFloat())
        onChange?.invoke()
    }

    /** Loads the audio and starts the decoder reading it. */
    fun prepare(from: PlaybackPosition? = null) {
        player.addListener(listener)
        player.setMediaItems(book.sources.map(::mediaItem))
        from?.let { seek(it) }
        player.prepare()
    }

    private fun mediaItem(part: Audiobook.AudioPart): MediaItem =
        MediaItem.Builder()
            .setUri(part.uri)
            .setMediaId("${book.id}:${part.uri}")
            .setMediaMetadata(
                androidx.media3.common.MediaMetadata.Builder()
                    .setTitle(book.title)
                    // The **chapter**, not the file. A product decision, recorded as one
                    // in `design.md`, and this is the line the lock screen and the shade
                    // both draw under the title.
                    .setSubtitle(part.title)
                    .setArtist(book.author)
                    .setArtworkUri(book.artworkUri?.let(android.net.Uri::parse))
                    .setIsBrowsable(false)
                    .setIsPlayable(true)
                    .setMediaType(
                        androidx.media3.common.MediaMetadata.MEDIA_TYPE_AUDIO_BOOK_CHAPTER,
                    )
                    .build(),
            )
            .build()

    /**
     * The parts before the decoder has said anything.
     *
     * A folder already knows: the format layer ordered its files and named them. A single
     * file does not, so it gets the one part `publication-formats` gives an unchaptered
     * audiobook — which is also the right answer if the marks never arrive.
     */
    private fun initialParts(): List<PlaybackPart> = when (book.layout) {
        PartLayout.FILES -> book.sources.map { PlaybackPart(it.title) }
        PartLayout.MARKS -> AudiobookChapters.parts(
            marks = emptyList(),
            totalMillis = null,
            fallbackTitle = book.title,
            chapterWord = chapterWord,
        )
    }

    /**
     * Takes the container's own chapter marks, once the decoder has read them.
     *
     * **Where they arrive is the part worth writing down.** media3 does not put chapters on
     * `MediaMetadata`; a `Chapter` is a `Metadata.Entry` hung off a track's `Format`, so
     * they come with the tracks and not with the item. `Chapter` is `@UnstableApi` at
     * 1.11.0 — see the change's task list — which is why the opt-in is here and at one
     * place only.
     *
     * A folder is left alone: its parts are its files, they were ordered and named by the
     * format layer, and a chapter mark inside part three is not a part of the book.
     */
    @OptIn(UnstableApi::class)
    private fun adoptChapters(tracks: Tracks) {
        if (book.layout != PartLayout.MARKS) return

        val marks = tracks.groups
            .flatMap { group -> (0 until group.length).map(group::getTrackFormat) }
            .mapNotNull { it.metadata }
            .flatMap { metadata -> (0 until metadata.length()).map(metadata::get) }
            .filterIsInstance<Chapter>()
            .map { chapter ->
                ChapterMark(
                    title = chapter.title?.value,
                    startMillis = chapter.startTimeMs,
                    endMillis = chapter.endTimeMs,
                    isHidden = chapter.isHidden,
                )
            }

        val duration = player.duration.takeIf { it != C.TIME_UNSET }
        parts = AudiobookChapters.parts(marks, duration, book.title, chapterWord)
        offsets = AudiobookChapters.offsets(marks)
        onChange?.invoke()
    }

    /**
     * Takes a folder's part lengths from the decoder, because nothing else has them.
     *
     * **Where they are is the part worth writing down.** media3 has no per-item duration
     * API: `Player.getDuration()` answers for the item playing, and the only place the rest
     * are is a `Timeline`'s windows, which arrive as a timeline change once the source has
     * been read. The format layer deliberately does not measure them — `OpenedAudiobook`
     * records why, an extractor per file would cost a five-hundred-book library a decode
     * pass per scan — so a folder starts with three unmeasured parts and learns.
     *
     * **What this unlocks is more than a number on a row.** A skip across a file boundary,
     * the whole-publication progress line, and *end of chapter* on the sleep timer all ask
     * `PlaybackPart.duration` and all answer "unknown" for a folder without this.
     *
     * A single file is left alone: its one window is the whole book, and adopting it as the
     * current part's length would give a three-chapter book one part the length of three.
     * A timeline whose window count is not the playlist's is not this book's — media3
     * reports an empty one before it has read anything — and adopting it would throw away
     * the names the format layer supplied.
     */
    private fun adoptDurations(timeline: Timeline) {
        if (book.layout != PartLayout.FILES) return
        if (timeline.windowCount != book.sources.size) return

        val durations = timeline.partDurations()
        val measured = book.sources.mapIndexed { index, part ->
            PlaybackPart(title = part.title, duration = durations[index])
        }
        if (measured == parts) return
        parts = measured
        onChange?.invoke()
    }
}
