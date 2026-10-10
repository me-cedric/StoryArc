package app.storyarc.core.playback

import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Headphones pulled out while a book plays, on the device that owns the decoder.
 *
 * Task 3.9. `NoisyBroadcastTest` sends the broadcast to the service's player on the host;
 * this plays a real file and sends the real action to a real session.
 *
 * **`ACTION_AUDIO_BECOMING_NOISY` is a protected broadcast.** Only the system, or a root shell,
 * may send it, so the case sends it through `am broadcast` and skips, with the command in the
 * message, where the shell is refused. Run it on a userdebug image after `adb root`. A device
 * whose player does not start the fixture is skipped for the reason `PlaybackResumeInstrumentedTest`
 * gives.
 */
@RunWith(AndroidJUnit4::class)
class PlaybackNoisyInstrumentedTest {

    @After
    fun endTheSession() {
        instrumentation.runOnMainSync { PlaybackHost.stop() }
    }

    @Test
    fun headphonesPulledOutPauseTheBookAsTheListenerAndItStaysSilent() {
        val book = Audiobook(
            id = "noisy-fixture",
            title = "Sea Room",
            sources = listOf(Audiobook.AudioPart(uri = fixtureUri(), title = "Sea Room")),
        )
        instrumentation.runOnMainSync { PlaybackHost.start(context, book) }
        awaitPlaying(true) ?: Assume.assumeTrue(
            "This device's player never started the fixture, so there is no book to pause.",
            false,
        )

        val answer = shell("am broadcast -a $NOISY")
        Assume.assumeFalse(
            "The shell may not send a protected broadcast here. Run `adb root`, then this case again. It said: $answer",
            answer.contains("Permission Denial", ignoreCase = true) || answer.contains("SecurityException"),
        )

        val paused = awaitPlaying(false)
        assertTrue("the book kept playing after the broadcast", paused != null)
        assertEquals(
            "the pause was recorded as an interruption, which a call's end would undo",
            PauseCause.LISTENER,
            paused?.session?.pausedBy,
        )

        // Silence afterwards: nothing the platform sends next starts it. Two seconds is longer
        // than the decoder takes to answer a focus gain.
        Thread.sleep(SILENCE_MILLIS)
        assertFalse("the book started again by itself", PlaybackHost.nowPlaying.value?.isPlaying == true)
    }

    /** The first report with the wanted playing state, or null at the deadline. */
    private fun awaitPlaying(wanted: Boolean): NowPlaying? {
        val deadline = System.currentTimeMillis() + TIMEOUT_MILLIS
        while (System.currentTimeMillis() < deadline) {
            PlaybackHost.nowPlaying.value?.takeIf { it.isPlaying == wanted }?.let { return it }
            Thread.sleep(POLL_MILLIS)
        }
        return null
    }

    /**
     * What the shell printed, standard error included. `am` prints its refusal of a protected
     * broadcast to standard error. A reader of standard output alone saw no refusal, did not
     * skip, and waited out the timeout for a pause that could not come: the CI failure from
     * 2026-10-07.
     */
    private fun shell(command: String): String {
        val (output, input, error) = instrumentation.uiAutomation.executeShellCommandRwe(command)
        input.close()
        return listOf(output, error).joinToString("\n") { descriptor ->
            ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { it.readText() }
        }
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
        const val NOISY = "android.media.AUDIO_BECOMING_NOISY"
        const val TIMEOUT_MILLIS = 20_000L
        const val POLL_MILLIS = 25L
        const val SILENCE_MILLIS = 2_000L
    }
}
