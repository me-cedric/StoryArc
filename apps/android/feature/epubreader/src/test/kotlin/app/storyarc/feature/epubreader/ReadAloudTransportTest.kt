package app.storyarc.feature.epubreader

import android.app.Notification
import android.content.Intent
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config

/**
 * What the reader reaches while the screen is off.
 *
 * `ebook-reader`, *Background and lock screen*:
 *
 * > **THEN** playback continues, and platform media controls show the publication title and
 * > offer play, pause, and sentence skip
 * > **AND** the second line names the chapter being spoken, or the author where the
 * > publication declares no navigation
 *
 * The second line was the only part any test touched. `SpokenLabel` decides what it says and
 * `ReadAloudSessionTest` asserts that. This file asserts the other three: the title, the three
 * buttons, and where each button goes.
 *
 * **The notification carries the `MediaSession` token that the shade draws its controls
 * from,** so a test that reads the notification reads what the shade offers. Android 13 and
 * later draws the lock screen from the session's own `PlaybackState` actions and `Callback`
 * instead, a path Robolectric's `MediaSession` shadow does not reflect back to a
 * `MediaController` — so that path is not asserted here.
 *
 * Robolectric, because a transport is a foreground service and a `Service` is a stub in the
 * plain unit-test JVM. iOS answers the same clause from `TransportCommands`, which says which
 * remote commands a spoken source turns on.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37; 34 is above the app's minimum.
@Config(sdk = [34])
class ReadAloudTransportTest {

    private val context = RuntimeEnvironment.getApplication()

    /** Whoever is speaking, replaced by a recorder of what the buttons asked for. */
    private class Pressed : ReadAloudCommands {
        val calls = mutableListOf<String>()

        override fun toggle() { calls += "toggle" }
        override fun skip(forward: Boolean) { calls += if (forward) "next" else "previous" }
        override fun stop() { calls += "stop" }
    }

    private val book = SpokenBook(
        id = "sea-room",
        location = "/books/sea-room.epub",
        title = "Sea Room",
        series = null,
        author = "Adam Nicolson",
        chapter = "Chapter Two",
    )

    private var service: ServiceController<ReadAloudService>? = null

    @After
    fun quiet() {
        ReadAloudService.commands = null
        service?.destroy()
        service = null
    }

    /** Starts the transport the way the session starts it, and returns what it posted. */
    private fun transport(isSpeaking: Boolean): Notification {
        ReadAloudService.show(context, book, isSpeaking)
        val started = requireNotNull(shadowOf(context).nextStartedService) {
            "ReadAloudService.show started no service, so there is no transport to read."
        }
        val controller = Robolectric.buildService(ReadAloudService::class.java, started).create()
        service = controller
        controller.startCommand(0, 0)
        return requireNotNull(shadowOf(controller.get()).lastForegroundNotification) {
            "The transport posted no foreground notification, so the voice does not survive" +
                " the reader leaving the app."
        }
    }

    /** Sends a button's own intent back to the service, as pressing it does. */
    private fun press(action: Notification.Action) {
        val sent: Intent = shadowOf(action.actionIntent).savedIntent
        requireNotNull(service).get().onStartCommand(sent, 0, 0)
    }

    @Test
    fun `the transport names the publication and the chapter being spoken`() {
        val transport = transport(isSpeaking = true)

        assertEquals("Sea Room", transport.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("Chapter Two", transport.extras.getString(Notification.EXTRA_TEXT))
    }

    /**
     * Three buttons, and the middle one says which of play and pause it is.
     *
     * A voice has no track list, so the two skips are sentence skips — which is why their
     * names say *sentence*. `ebook-reader` asks for play, pause and sentence skip, and this
     * is all three.
     */
    @Test
    fun `the transport offers sentence skip either side of pause while it speaks`() {
        val transport = transport(isSpeaking = true)

        assertEquals(3, transport.actions.size)
        assertEquals("Previous sentence", transport.actions[0].title.toString())
        assertEquals("Pause reading aloud", transport.actions[1].title.toString())
        assertEquals("Next sentence", transport.actions[2].title.toString())
    }

    /** The same three controls when the voice is paused, with play in place of pause. */
    @Test
    fun `the transport offers play while the voice is paused`() {
        val transport = transport(isSpeaking = false)

        assertEquals(3, transport.actions.size)
        assertEquals("Previous sentence", transport.actions[0].title.toString())
        assertEquals("Continue reading aloud", transport.actions[1].title.toString())
        assertEquals("Next sentence", transport.actions[2].title.toString())
    }

    /**
     * And each button reaches what its name says.
     *
     * The control this test needs: a transport that drew three buttons and wired all three to
     * one command would pass every assertion above.
     */
    @Test
    fun `each transport button reaches the voice it names`() {
        val transport = transport(isSpeaking = true)
        val pressed = Pressed()
        ReadAloudService.commands = pressed

        transport.actions.forEach(::press)

        assertEquals(listOf("previous", "toggle", "next"), pressed.calls)
    }

    /** The way back to the book, which a transport that outlives its screen has to carry. */
    @Test
    fun `the transport carries the way back to the publication`() {
        val transport = transport(isSpeaking = true)

        assertNotNull(
            "The transport offers no way back to the book it is speaking.",
            transport.contentIntent,
        )
    }
}
