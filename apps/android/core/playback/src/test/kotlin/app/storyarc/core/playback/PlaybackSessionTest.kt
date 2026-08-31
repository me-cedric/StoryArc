package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * One session, two sources, and a surface that cannot tell which is behind it.
 *
 * `audio-playback`: "every source of spoken audio — a narrated audiobook and the
 * read-aloud voice alike — SHALL drive that one surface". The way to assert that is not
 * to look at the type of the source but to drive **the same assertions over both** and
 * require the same answers, which is what the parameterised cases below do.
 *
 * iOS's `PlaybackSessionTests` asserts the same table.
 */
class PlaybackSessionTest {

    // MARK: 1.1 — two sources, one set of assertions

    /**
     * The two implementations the design names: a narrated file and a synthesised voice.
     *
     * A narrated part knows how long it is; a spoken one does not. Everything else about
     * them is identical, and everything the surfaces read is built from that.
     */
    private fun narrated() = FakeSource(
        publicationId = "sea-room",
        title = "Sea Room",
        parts = listOf(
            PlaybackPart("One", PlaybackDuration.Known(120_000)),
            PlaybackPart("Two", PlaybackDuration.Known(180_000)),
        ),
    )

    private fun spoken() = FakeSource(
        publicationId = "sea-room",
        title = "Sea Room",
        parts = listOf(
            PlaybackPart("One", PlaybackDuration.Estimated(120_000)),
            PlaybackPart("Two", PlaybackDuration.Estimated(180_000)),
        ),
    )

    @Test
    fun `both sources produce the same surface`() {
        for (source in listOf(narrated(), spoken())) {
            val centre = PlaybackCentre()
            centre.start(source)

            val playing = centre.nowPlaying!!
            // Everything a surface draws, and there is nothing else on the value: no
            // field names the engine, so a bar built from this cannot state one.
            assertEquals("Sea Room", playing.title)
            assertEquals("One", playing.chapter)
            assertEquals(0, playing.partIndex)
            assertEquals(0L, playing.offsetMillis)
            assertTrue(playing.isPlaying)
            assertEquals(PlaybackSpeed.NORMAL, playing.speed)

            centre.toggle()
            assertFalse(centre.nowPlaying!!.isPlaying)
            assertTrue(centre.nowPlaying!!.isActive)

            centre.toggle()
            assertTrue(centre.nowPlaying!!.isPlaying)
        }
    }

    @Test
    fun `a publication with no chapter markers still names its parts`() {
        // `audio-playback`: a publication with no chapter markers "lists its parts in
        // playing order instead, rather than showing an empty list".
        val centre = PlaybackCentre()
        centre.start(
            FakeSource(
                publicationId = "unchaptered",
                title = "Unchaptered",
                parts = listOf(PlaybackPart("Unchaptered", PlaybackDuration.Known(5_000))),
            ),
        )
        assertEquals(listOf("Unchaptered"), centre.nowPlaying!!.parts.map { it.title })
        assertEquals("Unchaptered", centre.nowPlaying!!.chapter)
    }

    // MARK: 1.2 — parts, position, duration, speed

    @Test
    fun `a known duration is stated and offers a scrub`() {
        val duration = PlaybackDuration.Known(120_000)
        assertEquals(120_000L, duration.statedMillis)
        assertTrue(duration.isScrubbable)
    }

    @Test
    fun `an estimated duration is never stated as a total and offers no scrub`() {
        // The design's own line: a read-aloud session's duration is "estimated from
        // characters and rate, and never presented as exact". So the estimate exists —
        // a progress line can lean on it — and `statedMillis` is null, which is what a
        // surface asks before it draws a total.
        val duration = PlaybackDuration.Estimated(120_000)
        assertNull(duration.statedMillis)
        assertFalse(duration.isScrubbable)
        assertEquals(120_000L, duration.estimatedMillis)
    }

    @Test
    fun `a source with no known duration reports position without a total`() {
        // Task 1.2, word for word: "a source with no known duration reports position
        // without a total rather than inventing one".
        val centre = PlaybackCentre()
        centre.start(spoken())
        centre.seek(PlaybackPosition(partIndex = 0, offsetMillis = 30_000))

        val playing = centre.nowPlaying!!
        assertEquals(30_000L, playing.offsetMillis)
        assertNull(playing.statedPartDurationMillis)
        assertNull(playing.statedTotalMillis)
        assertFalse(playing.isScrubbable)
    }

    @Test
    fun `a narrated source reports a total across its parts`() {
        val centre = PlaybackCentre()
        centre.start(narrated())
        centre.seek(PlaybackPosition(partIndex = 1, offsetMillis = 30_000))

        val playing = centre.nowPlaying!!
        assertEquals(180_000L, playing.statedPartDurationMillis)
        assertEquals(300_000L, playing.statedTotalMillis)
        // 120 s of part one, plus 30 s into part two.
        assertEquals(150_000L, playing.elapsedTotalMillis)
        assertTrue(playing.isScrubbable)
    }

    @Test
    fun `one unknown part duration makes the whole total unknown`() {
        // Half a total is worse than none: a progress line drawn against a total that
        // omits a part would run past its own end.
        val centre = PlaybackCentre()
        centre.start(
            FakeSource(
                publicationId = "half-known",
                title = "Half Known",
                parts = listOf(
                    PlaybackPart("One", PlaybackDuration.Known(120_000)),
                    PlaybackPart("Two", PlaybackDuration.Unknown),
                ),
            ),
        )
        assertNull(centre.nowPlaying!!.statedTotalMillis)
        assertNull(centre.nowPlaying!!.elapsedTotalMillis)
    }

    @Test
    fun `speed is carried on the surface and reaches the source`() {
        val source = narrated()
        val centre = PlaybackCentre()
        centre.start(source)
        centre.setSpeed(PlaybackSpeed.of(1.5))

        assertEquals(1.5, centre.nowPlaying!!.speed.rate, 0.0001)
        assertEquals(1.5, source.speed.rate, 0.0001)
    }

    // MARK: 1.3 — one thing at a time

    @Test
    fun `starting a second publication stops the first and records it first`() {
        // `audio-playback`: "the first stops and its position is recorded before the
        // second begins, because two books speaking at once is never what was meant".
        // The *order* is the assertion — a position written after the new source has
        // started is a position written for the wrong book.
        val log = mutableListOf<String>()
        val first = FakeSource(
            publicationId = "sea-room",
            title = "Sea Room",
            parts = listOf(PlaybackPart("One", PlaybackDuration.Known(120_000))),
            log = log,
        )
        val second = FakeSource(
            publicationId = "the-peregrine",
            title = "The Peregrine",
            parts = listOf(PlaybackPart("One", PlaybackDuration.Known(120_000))),
            log = log,
        )

        val centre = PlaybackCentre(
            record = { source, position ->
                log += "recorded ${source.publicationId}@${position.offsetMillis}"
            },
        )
        centre.start(first)
        centre.seek(PlaybackPosition(partIndex = 0, offsetMillis = 42_000))
        log.clear()
        centre.start(second)

        assertEquals(
            listOf("recorded sea-room@42000", "stopped sea-room", "played the-peregrine"),
            log,
        )
        assertEquals("the-peregrine", centre.nowPlaying!!.publicationId)
    }

    @Test
    fun `the displaced publication is not resumed when the second ends`() {
        val centre = PlaybackCentre()
        centre.start(narrated())
        centre.start(
            FakeSource(
                publicationId = "the-peregrine",
                title = "The Peregrine",
                parts = listOf(PlaybackPart("One", PlaybackDuration.Known(120_000))),
            ),
        )
        centre.stop()

        // Nothing plays, and nothing is queued behind it.
        assertNull(centre.nowPlaying)
    }

    @Test
    fun `reaching the end takes the surface away`() {
        // `audio-playback`, by way of `ebook-reader`: at the end "the highlight is
        // withdrawn, and the media controls go away … and the compact bar goes away with
        // them". A null surface is what "goes away" is, so it is asserted as one.
        val source = narrated()
        val centre = PlaybackCentre()
        centre.start(source)
        source.reachEnd()

        assertNull(centre.nowPlaying)
    }

    // MARK: the session table, shared with read-aloud
    //
    // These cases came here from `:feature:epubreader`'s `ReadAloudSessionTest` when the
    // table moved. They are the same cases, in the same order, and iOS pins them too.

    private val idle = PlaybackSession()
    private val playing = idle.started()

    @Test
    fun `a session begins silent`() {
        assertEquals(PlaybackState.IDLE, idle.state)
        assertFalse(idle.isPlaying)
        assertFalse(idle.isActive)
    }

    @Test
    fun `starting plays`() {
        assertEquals(PlaybackState.PLAYING, playing.state)
        assertTrue(playing.isPlaying)
        assertNull(playing.pausedBy)
    }

    @Test
    fun `a paused session still offers its controls`() {
        assertTrue(playing.pausedByListener().isActive)
        assertFalse(playing.pausedByListener().isPlaying)
    }

    @Test
    fun `the listener can start it again`() {
        assertEquals(PlaybackState.PLAYING, playing.pausedByListener().resumed().state)
    }

    @Test
    fun `an interruption pauses and says so`() {
        val paused = playing.interrupted()
        assertEquals(PlaybackState.PAUSED, paused.state)
        assertEquals(PauseCause.INTERRUPTION, paused.pausedBy)
    }

    /** The case this type exists for: a notification must not undo a deliberate pause. */
    @Test
    fun `an interruption never touches a pause the listener made`() {
        val paused = playing.pausedByListener()
        assertEquals(paused, paused.interrupted())
    }

    @Test
    fun `audio taken for good stops it rather than holding it`() {
        assertEquals(PlaybackState.IDLE, playing.lostAudio().state)
        assertEquals(PlaybackState.IDLE, playing.interrupted().lostAudio().state)
    }

    @Test
    fun `stopping clears the cause with the state`() {
        val stopped = playing.interrupted().stopped()
        assertEquals(PlaybackState.IDLE, stopped.state)
        assertNull(stopped.pausedBy)
    }

    @Test
    fun `nothing resumes a session that was never started`() {
        assertEquals(idle, idle.resumed())
        assertEquals(idle, idle.pausedByListener())
        assertEquals(idle, idle.interrupted())
    }

    // One publication at a time.

    @Test
    fun `opening a publication while nothing plays starts silent`() {
        assertEquals(SessionHandover.NONE, SessionHandover.opening("sea-room", null))
    }

    /**
     * Closing the publication mid-chapter and coming back to it: the listener picks the
     * session up rather than starting a second one on the same book.
     */
    @Test
    fun `reopening the publication being played adopts the session`() {
        assertEquals(SessionHandover.ADOPT, SessionHandover.opening("sea-room", "sea-room"))
    }

    @Test
    fun `opening a different publication displaces it`() {
        assertEquals(
            SessionHandover.DISPLACE,
            SessionHandover.opening("the-peregrine", "sea-room"),
        )
    }

    @Test
    fun `a pause the listener made is never undone by an interruption ending`() {
        val paused = PlaybackSession().started().pausedByListener()
        assertEquals(PauseCause.LISTENER, paused.pausedBy)
        assertEquals(InterruptionOutcome.NOTHING, paused.endingInterruption(mayResume = true))
    }

    @Test
    fun `an interruption that may resume gives the audio back`() {
        val paused = PlaybackSession().started().interrupted()
        assertEquals(PauseCause.INTERRUPTION, paused.pausedBy)
        assertEquals(InterruptionOutcome.RESUME, paused.endingInterruption(mayResume = true))
    }

    @Test
    fun `audio taken for good ends the session whoever silenced it`() {
        val byListener = PlaybackSession().started().pausedByListener()
        val byInterruption = PlaybackSession().started().interrupted()
        assertEquals(InterruptionOutcome.LOST, byListener.endingInterruption(mayResume = false))
        assertEquals(InterruptionOutcome.LOST, byInterruption.endingInterruption(mayResume = false))
        assertEquals(
            InterruptionOutcome.NOTHING,
            PlaybackSession().endingInterruption(mayResume = false),
        )
    }
}

/**
 * A source with no engine behind it.
 *
 * Stands for both implementations: what separates a narrated file from a synthesised
 * voice, as far as everything above them is concerned, is whether its parts know how long
 * they are — which is a value, so one fake with two part lists is the honest double
 * rather than two fakes that would drift apart.
 */
private class FakeSource(
    override val publicationId: String,
    override val title: String,
    override val parts: List<PlaybackPart>,
    private val log: MutableList<String>? = null,
) : PlayerSource {

    override var position: PlaybackPosition = PlaybackPosition(0, 0)
        private set

    override var session: PlaybackSession = PlaybackSession()
        private set

    override var speed: PlaybackSpeed = PlaybackSpeed.NORMAL
        private set

    override var onChange: (() -> Unit)? = null

    override fun play() {
        log?.add("played $publicationId")
        session = session.started()
        onChange?.invoke()
    }

    override fun pause() {
        session = session.pausedByListener()
        onChange?.invoke()
    }

    override fun stop() {
        log?.add("stopped $publicationId")
        session = session.stopped()
        onChange?.invoke()
    }

    override fun seek(to: PlaybackPosition) {
        position = to
        onChange?.invoke()
    }

    override fun setSpeed(speed: PlaybackSpeed) {
        this.speed = speed
        onChange?.invoke()
    }

    /** The book ran out of words. */
    fun reachEnd() {
        session = session.stopped()
        onChange?.invoke()
    }
}
