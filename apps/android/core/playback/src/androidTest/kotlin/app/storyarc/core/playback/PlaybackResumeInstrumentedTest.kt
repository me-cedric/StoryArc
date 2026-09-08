package app.storyarc.core.playback

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A book started at a saved position, on the device that owns the decoder.
 *
 * A host test cannot answer this. The seek crosses a `MediaController` to a service, and the
 * position comes back out of the platform's own MP4 extractor. Both are stubs off a device,
 * so the one mechanism `reading-progress` asks for went unproved until this ran on hardware.
 */
@RunWith(AndroidJUnit4::class)
class PlaybackResumeInstrumentedTest {

    @After
    fun endTheSession() {
        instrumentation.runOnMainSync { PlaybackHost.stop() }
    }

    @Test
    fun aBookStartedAtASavedPositionPlaysFromThatChapterAndNotFromZero() {
        val book = Audiobook(
            id = "resume-fixture",
            title = "Sea Room",
            sources = listOf(Audiobook.AudioPart(uri = fixtureUri(), title = "Sea Room")),
        )

        instrumentation.runOnMainSync {
            PlaybackHost.start(context, book, from = PlaybackPosition(1, SAVED_MILLIS))
        }
        val playing = awaitChapters()

        assertTrue(
            "The player reported ${playing.offsetMillis} ms in chapter ${playing.chapter}." +
                " A saved position of $SAVED_MILLIS ms must land inside the second chapter.",
            playing.offsetMillis >= SAVED_MILLIS && playing.offsetMillis < CHAPTER_THREE_MILLIS,
        )
        assertEquals("Two", playing.chapter)
        assertEquals(1, playing.partIndex)
    }

    /**
     * The first report that carries the container's own marks.
     *
     * The marks arrive with the tracks, one callback after the seek, and the chapter a
     * listener lands in is unanswerable before them.
     */
    private fun awaitChapters(): NowPlaying {
        val deadline = System.currentTimeMillis() + TIMEOUT_MILLIS
        while (System.currentTimeMillis() < deadline) {
            PlaybackHost.nowPlaying.value
                ?.takeIf { it.parts.size == CHAPTERS }
                ?.let { return it }
            Thread.sleep(POLL_MILLIS)
        }
        throw AssertionError("The player never reported the fixture's $CHAPTERS chapters.")
    }

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    private val context get() = instrumentation.context

    private fun fixtureUri(): String {
        val target = File(context.cacheDir, FIXTURE.substringAfterLast('/'))
        if (!target.exists()) {
            context.assets.open(FIXTURE).use { input -> target.outputStream().use(input::copyTo) }
        }
        return Uri.fromFile(target).toString()
    }

    private companion object {
        const val FIXTURE = "audiobooks/chaptered.m4b"
        const val CHAPTERS = 3
        const val SAVED_MILLIS = 2_000L
        const val CHAPTER_THREE_MILLIS = 4_000L
        const val TIMEOUT_MILLIS = 3_000L
        const val POLL_MILLIS = 25L
    }
}
