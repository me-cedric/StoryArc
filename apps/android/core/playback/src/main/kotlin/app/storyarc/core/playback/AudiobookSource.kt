package app.storyarc.core.playback

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.Tracks

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
            // One item, so the part is wherever the position falls between the marks, and
            // the offset is measured from that mark. The unit is the part, exactly as it is
            // for a folder: `PlaybackPosition` states one unit and iOS's
            // `PlaybackTimeline.place(atFileTime:)` answers in the same one.
            PartLayout.MARKS -> placeOf(player.currentPosition.coerceAtLeast(0))
        }

    /**
     * The mark the current chapter starts at, which is where [position] measures from.
     *
     * A media3 seek takes a time into the item, so this is what converts a part offset back
     * into one: [fileTimeOf] adds it, and [PlaybackMemory] stores the sum. `offsets` is
     * index-aligned with `parts`, and `AudiobookChaptersTest` pins that alignment.
     */
    override val partStartMillis: Long
        get() = when (book.layout) {
            PartLayout.FILES -> 0
            PartLayout.MARKS -> offsets.getOrElse(position.partIndex) { 0 }
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
            // The mark, plus how far into the chapter the caller asked for. A media3 seek
            // takes a time into the item and a `PlaybackPosition` states a time into a part,
            // so this is the one place the two units meet.
            PartLayout.MARKS -> player.seekTo(fileTimeOf(to))
        }
        onChange?.invoke()
    }

    /** Where a part offset falls in the one file a `MARKS` book is. */
    private fun fileTimeOf(place: PlaybackPosition): Long =
        offsets.getOrElse(place.partIndex) { 0L } + place.offsetMillis.coerceAtLeast(0)

    /** Which part a file time is in, and how far into that part. */
    private fun placeOf(fileTimeMillis: Long): PlaybackPosition {
        val part = AudiobookChapters.partAt(offsets, fileTimeMillis)
        return PlaybackPosition(
            partIndex = part,
            offsetMillis = (fileTimeMillis - offsets.getOrElse(part) { 0L }).coerceAtLeast(0),
        )
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
                seek(placeOf(target))
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

    /**
     * Loads the audio and starts the decoder reading it, at the place the listener left.
     *
     * **The position goes in with the items, and that is the whole of Android's resumption
     * defect.** This used to set the items and then [seek], and a phone measured the result:
     * `COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM` is not among a `MediaController`'s available
     * commands while the service's player holds no audio, so `MediaController.seekTo` was
     * dropped locally and never crossed to the session. The book began at zero every time,
     * and `reading-progress`' "returns to where they were" was untrue on the live path —
     * only the dead-process path in [PlaybackService.Resumption] carried a position.
     * Measured on an HD1911, API 34: `canSeek=false`, `after=0`.
     *
     * One command instead of two. `setMediaItems` needs only `COMMAND_CHANGE_MEDIA_ITEMS`,
     * which a controller does hold with an empty player, and it carries the start position
     * itself. The index is the item's, never the part's: a single file's marks are all in
     * item zero.
     *
     * **A chapter of a single file needs the marks, and the marks arrive with the audio.**
     * The offset handed in is a time into a part, and turning it into a time into the file
     * takes `offsets`, which [adoptChapters] fills once the decoder has read the container.
     * So the position goes in as it stands — right for the first chapter and for a file with
     * no marks at all — and [pending] carries the rest to [adoptChapters], which seeks the
     * moment the arithmetic becomes possible. By then the player holds audio, so the seek
     * command the resumption defect was about is available.
     */
    fun prepare(from: PlaybackPosition? = null) {
        player.addListener(listener)
        val index = if (book.layout == PartLayout.FILES) from?.partIndex ?: 0 else 0
        pending = from?.takeIf { book.layout == PartLayout.MARKS && it.partIndex > 0 }
        player.setMediaItems(book.sources.map(::mediaItem), index, from?.offsetMillis ?: C.TIME_UNSET)
        player.prepare()
    }

    /** A part offset waiting for the marks that place it. See [prepare]. */
    private var pending: PlaybackPosition? = null

    /** The picture the session shows: the book's own, until the player has drawn one. */
    private var artwork: Uri? = book.artworkUri?.let(Uri::parse)

    /**
     * Gives the items the picture the player drew, without touching the audio.
     *
     * `replaceMediaItems` over items whose locations have not changed is a metadata update
     * and not a reload: ExoPlayer asks each source whether it can take the new item, and a
     * progressive source can when the URI, the cache key and the DRM are the same, so the
     * audio neither stops, seeks nor buffers. That is what lets the picture arrive a second
     * after the first sound without breaking `audio-playback`'s "never restarts, reloads or
     * repositions the audio" — the clause the whole player is built around.
     */
    fun setArtwork(uri: Uri) {
        if (uri == artwork) return
        artwork = uri
        val items = book.sources.map(::mediaItem)
        // The playlist is this book's or it is nobody's business to rewrite. A count that
        // differs means the player is already carrying something else.
        if (player.mediaItemCount != items.size) return
        player.replaceMediaItems(0, items.size, items)
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
                    .setArtworkUri(artwork)
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
     * they come with the tracks and not with the item. [ChapterMarks] holds the filter and
     * the `@UnstableApi` opt-in that reading a `Chapter` needs, because a page reads the
     * same marks out of the same formats before anything plays — and two copies of a
     * chapter parser is the drift this repository keeps finding.
     *
     * A folder is left alone: its parts are its files, they were ordered and named by the
     * format layer, and a chapter mark inside part three is not a part of the book.
     */
    private fun adoptChapters(tracks: Tracks) {
        if (book.layout != PartLayout.MARKS) return

        val marks = ChapterMarks.of(tracks)
        val duration = player.duration.takeIf { it != C.TIME_UNSET }
        parts = AudiobookChapters.parts(marks, duration, book.title, chapterWord)
        offsets = AudiobookChapters.offsets(marks)
        // The place [prepare] could not reach. Taken before the seek rather than after it:
        // `seek` publishes, and a second pass through here must not seek back again.
        val resume = pending
        pending = null
        if (resume != null) seek(resume) else onChange?.invoke()
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
