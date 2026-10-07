package app.storyarc.core.playback

/**
 * The one session, and the one thing that owns it.
 *
 * Every surface observes [nowPlaying]; every source is driven through here. That is what
 * makes "one player, two sources" true rather than intended: there is one place a source
 * can be started from, and it stops whatever was playing first.
 *
 * A class rather than an `object`, so the rules below can be asserted without a process.
 * The app holds one instance — see the platform's own player service, which is what keeps
 * it alive once every screen has gone.
 *
 * @param record where a position goes when a session gives it up. Called **before** the
 *   next source plays a sound, which is the ordering `audio-playback` asks for by name.
 */
class PlaybackCentre(
    private val record: (PlayerSource, PlaybackPosition) -> Unit = { _, _ -> },
) {

    private var source: PlayerSource? = null

    /** What every surface draws, or null when nothing is playing. */
    var nowPlaying: NowPlaying? = null
        private set

    /** Told whenever [nowPlaying] changes, so a surface can redraw. */
    var onChange: ((NowPlaying?) -> Unit)? = null

    /**
     * What the last session to end left unplayed, kept past the teardown that clears
     * [nowPlaying]. Task 2.5, owner answer O12: a book whose last or only part fails ends here,
     * and the finished state of the player still states how much could not be played. Cleared
     * when the next source is held.
     */
    var lastEnding: Ending? = null
        private set

    /** A session that has ended: which publication, and how many of its parts did not play. */
    data class Ending(val publicationId: String, val unplayedParts: Int)

    /** The id of the publication being played, or null. Feeds [SessionHandover.opening]. */
    val playingId: String? get() = source?.publicationId

    /**
     * The publication being played as [SpokenAudio] sees it — the id [playingId] already
     * answers, with the title a displacement notice names beside it — or null.
     */
    val playing: SpokenAudio.Spoken?
        get() = source?.let { SpokenAudio.Spoken(it.publicationId, it.title) }

    /**
     * Plays a publication, displacing whatever was playing.
     *
     * The order is the requirement: the outgoing position is written, *then* the outgoing
     * source is stopped, *then* the new one plays. A position written after the new source
     * started would be a position written against the wrong book.
     */
    fun start(source: PlayerSource) {
        hold(source)
        source.play()
        publish()
    }

    /**
     * Adopts a source something else has already started, instead of starting one of this
     * centre's own through [start].
     *
     * [PlaybackService.LibraryCallback.onSetMediaItems] is the one caller: a car choosing a
     * book from the shelf hands it straight to the service player, with no [PlayerSource]
     * attached and nothing writing `reading-progress` for it. This is [start] without the
     * `source.play()` — the car's own session commands are what load and start the audio —
     * so a car-started book becomes the one session every other surface reads, instead of
     * sound this centre knows nothing about.
     */
    fun attach(source: PlayerSource) {
        hold(source)
        publish()
    }

    /** What [start] and [attach] share: displace whatever was playing, and hold the new one. */
    private fun hold(source: PlayerSource) {
        displace()
        lastEnding = null
        this.source = source
        source.onChange = { publish() }
        source.onInterruptionEnd = { mayResume -> endInterruption(mayResume) }
    }

    /**
     * The listener came back to the publication already playing.
     *
     * Answers [SessionHandover.ADOPT]: nothing is started, nothing is repositioned, and
     * the caller gets the surface it should draw.
     */
    fun adopt(publicationId: String): NowPlaying? =
        if (playingId == publicationId) nowPlaying else null

    /**
     * Pause and play, from wherever the listener reached for it.
     *
     * The pause's own write is not here. It is in [publish], because this is only one of the
     * ways a book is paused — see the note there.
     */
    fun toggle() {
        val source = source ?: return
        if (source.session.isPlaying) source.pause() else source.play()
        publish()
    }

    /**
     * Writes where the audio has reached, read from the player at this moment.
     *
     * **The read is the whole of it.** [PlayerSource.position] asks the player itself, so
     * this is the position the audio is at. A caller that built one from [nowPlaying] would
     * store a snapshot instead — that value only moves when the player reports a callback,
     * so a book playing steadily through one long file holds the offset it started at, and a
     * write of it looks like a fix and stores nothing new.
     *
     * For the moments a listener expects to be remembered: a pause, a jump they chose, the
     * app leaving the foreground, and the periodic floor underneath all three.
     */
    fun recordReached() {
        val source = source ?: return
        record(source, source.position)
    }

    /**
     * Rebuilds the surface from the player, for a caller that knows time has passed.
     *
     * media3 raises a callback for a seek, a transition and a pause. It raises none for the
     * clock running on, so [nowPlaying] holds the offset a file started at for as long as
     * that file plays — measured on 2026-09-08, and pinned by `RecordedPositionTest`. A
     * chapter list that states how much of a chapter is left reads that offset, so the
     * number would freeze where the audio began. The app's own fifteen-second tick calls
     * this, so no loop is added here.
     *
     * **Never call this from [recordReached].** [publish] calls [recordReached] on the
     * transition into a listener pause and assigns [nowPlaying] after it, so pairing the
     * two recurses without end.
     */
    fun refresh() = publish()

    fun seek(to: PlaybackPosition) {
        source?.seek(to)
        publish()
    }

    /**
     * Moves by the fixed interval, crossing a part boundary rather than stopping.
     *
     * The carrying is [PlayerSource.skip]'s and the interval is [SkipIntervals]'s, which is
     * the split `design.md` draws: what a skip *moves* is the source's business, and how far
     * it moves is the session's. A source is told how far to move and never which number
     * that is, exactly as iOS's `PlayerCentre` tells it.
     */
    fun skip(direction: SkipDirection) {
        val source = source ?: return
        source.skip(direction, SkipIntervals.millis(direction))
        // The audio did not drift here, the listener chose it. [seek] deliberately does not
        // do this: the scrub control calls it on every pixel of a drag, and a position store
        // written sixty times a second is a different defect. The scrub writes when the drag
        // settles instead — see `PlayerScreen`'s `onValueChangeFinished`.
        recordReached()
        publish()
    }

    fun setSpeed(speed: PlaybackSpeed) {
        source?.setSpeed(speed)
        publish()
    }

    /**
     * Moves to the start of a chapter the listener chose from a list.
     *
     * Through the source, like every other transport call, rather than through the one
     * implementation the host happened to hold. The write is the requirement: choosing a
     * chapter is `audio-playback`'s "a listener deciding where they are".
     */
    fun seekToPart(index: Int) {
        val source = source ?: return
        source.seekToPart(index)
        recordReached()
        publish()
    }

    /** The sleep timer's fade, given to whatever is making the sound. See [PlayerSource.setVolume]. */
    fun setVolume(gain: Float) {
        source?.setVolume(gain)
    }

    /** The sleep timer's ending. See [PlayerSource.stopAtSentenceEnd]. */
    fun stopAtSentenceEnd() {
        source?.stopAtSentenceEnd()
        publish()
    }

    /** Ends the session: the listener closed it, or the book ran out of words. */
    fun stop() {
        val ending = source ?: return
        recordAndRelease(ending)
        publish()
    }

    /**
     * What the interruption's end does, decided by the shared table rather than here.
     *
     * The platform's audio callback calls this with its own answer to "may it resume",
     * and the three outcomes are the same three on both platforms.
     */
    fun endInterruption(mayResume: Boolean) {
        val source = source ?: return
        when (source.session.endingInterruption(mayResume)) {
            InterruptionOutcome.NOTHING -> Unit
            InterruptionOutcome.RESUME -> source.play()
            // Taken for good. The position is written, exactly as it is for a stop the
            // listener made: `audio-playback` asks for audio taken for good to end "the
            // session and record the position rather than leaving it paused for ever".
            InterruptionOutcome.LOST -> recordAndRelease(source)
        }
        publish()
    }

    private fun displace() {
        val outgoing = source ?: return
        recordAndRelease(outgoing)
    }

    private fun recordAndRelease(ending: PlayerSource) {
        if (source !== ending) return
        record(ending, ending.position)
        lastEnding = Ending(ending.publicationId, ending.skippedPartCount)
        // Detached before the stop, so the stop's own change does not republish a source
        // this centre has already given up.
        ending.onChange = null
        ending.onInterruptionEnd = null
        ending.stop()
        source = null
    }

    /**
     * Rebuilds the surface from the source, and lets it go when the source has ended.
     *
     * The end of a book arrives here as an idle session rather than as a call: media3
     * reports the end of the last item, and the speech engine reports running out of
     * words, and neither of them is a listener pressing stop. `audio-playback` wants the
     * same thing of both — the controls go away — so the surface is dropped here.
     *
     * **Through [recordAndRelease], because the teardown is the same teardown.** This used
     * to record the position and detach the callbacks inline and never call
     * [PlayerSource.stop], so a book that ran out left its engine exactly as it was: on the
     * narrated path the `Player.Listener` stayed on a `MediaController` that lives as long
     * as the process, and neither `player.stop()` nor `player.clearMediaItems()` ran, so the
     * finished playlist stayed loaded in the thing media3 draws its notification from. A
     * listener's own stop did all three. Two endings, one of them incomplete, and nothing
     * said which. iOS's `PlayerCentre.finish` has always been the one teardown for all
     * three endings — and for a spoken source `stop()` is the *only* signal that withdraws
     * the highlight, which is what this would have cost the moment read-aloud becomes a
     * second [PlayerSource] here.
     */
    private fun publish() {
        val source = source
        val next = when {
            source == null -> null
            !source.session.isActive -> {
                recordAndRelease(source)
                null
            }
            else -> NowPlaying.of(source)
        }
        if (next == nowPlaying) return
        // **The listener silenced it, so the position is written.** `audio-playback` asks for
        // a pause to be recorded, and here rather than in [toggle] because a toggle is only
        // one of the ways a book is paused: media3 hands a lock-screen, shade, car or headset
        // pause straight to the player it wraps, and this centre never hears the call — it
        // hears the *result*, which is this transition.
        //
        // A pause the *platform* made is left alone. An interruption is a book the listener
        // still means to hear, and the one that ends for good is recorded by
        // [recordAndRelease] on its way out.
        val becamePause = next.isListenerPause() && !nowPlaying.isListenerPause()
        // **A part crossed, so the position is written.** iOS's `recordDrifted` writes on
        // every part change for the same reason: a boundary is a landmark, and the offset
        // restarts at it. Without this the only write between the periodic tick is the
        // pause above, and a chapter mark crossed inside a single file — which raises no
        // other callback at all — went unrecorded until the next fifteen-second tick, or
        // never, if the session ended first. `nowPlaying` has to be non-null: a fresh start
        // moves the index from nothing to zero, and that is not a crossing.
        val crossedPart = next != null && nowPlaying != null && next.partIndex != nowPlaying?.partIndex
        // One write, however many of the above are true at once — a pause that lands exactly
        // on a part boundary is still one moment, not two writes of the same position.
        if (becamePause || crossedPart) recordReached()
        nowPlaying = next
        onChange?.invoke(next)
    }

    /** Whether this surface is a book the listener has silenced. */
    private fun NowPlaying?.isListenerPause(): Boolean =
        this != null && !isPlaying && session.pausedBy == PauseCause.LISTENER
}
