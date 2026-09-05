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
     * How far a skip moves. See [SkipIntervals] for why the defaults are what they are.
     *
     * Held here, and applied here, exactly as iOS's `PlayerCentre` holds it: a source is
     * told how far to move and never which number that is. One place decides, so the app's
     * control and the notification's cannot drift into skipping by different amounts.
     */
    var skipIntervals: SkipIntervals = SkipIntervals.DEFAULT

    /** The id of the publication being played, or null. Feeds [SessionHandover.opening]. */
    val playingId: String? get() = source?.publicationId

    /**
     * Plays a publication, displacing whatever was playing.
     *
     * The order is the requirement: the outgoing position is written, *then* the outgoing
     * source is stopped, *then* the new one plays. A position written after the new source
     * started would be a position written against the wrong book.
     */
    fun start(source: PlayerSource) {
        displace()
        this.source = source
        source.onChange = { publish() }
        source.onInterruptionEnd = { mayResume -> endInterruption(mayResume) }
        source.play()
        publish()
    }

    /**
     * The listener came back to the publication already playing.
     *
     * Answers [SessionHandover.ADOPT]: nothing is started, nothing is repositioned, and
     * the caller gets the surface it should draw.
     */
    fun adopt(publicationId: String): NowPlaying? =
        if (playingId == publicationId) nowPlaying else null

    /** Pause and play, from wherever the listener reached for it. */
    fun toggle() {
        val source = source ?: return
        if (source.session.isPlaying) source.pause() else source.play()
        publish()
    }

    fun seek(to: PlaybackPosition) {
        source?.seek(to)
        publish()
    }

    /**
     * Moves by the configured interval, crossing a part boundary rather than stopping.
     *
     * The carrying is [PlayerSource.skip]'s and the interval is [skipIntervals]'s, which is
     * the split `design.md` draws: what a skip *moves* is the source's business, and how far
     * it moves is the session's.
     */
    fun skip(direction: SkipDirection) {
        val source = source ?: return
        source.skip(direction, skipIntervals.millis(direction))
        publish()
    }

    fun setSpeed(speed: PlaybackSpeed) {
        source?.setSpeed(speed)
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
        nowPlaying = next
        onChange?.invoke(next)
    }
}
