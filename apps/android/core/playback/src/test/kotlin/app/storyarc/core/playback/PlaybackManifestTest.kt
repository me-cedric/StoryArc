package app.storyarc.core.playback

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.w3c.dom.Element

/**
 * What the module's manifest promises the system, read as XML.
 *
 * `audiobooks-and-playback` task 3.6: media3 resumes a dead session from a media button only
 * where the app declared its receiver, and says so by name in its background-playback guide.
 * `PlayerServiceIsDeclaredTest` asks the installed package the same question on a device; this
 * is the host half, so a manifest edit that drops the receiver fails in a second.
 */
class PlaybackManifestTest {

    private val manifest: Element = DocumentBuilderFactory.newInstance()
        .apply { isNamespaceAware = false }
        .newDocumentBuilder()
        .parse(File("src/main/AndroidManifest.xml"))
        .documentElement

    private fun receivers(): List<Element> {
        val nodes = manifest.getElementsByTagName("receiver")
        return (0 until nodes.length).map { nodes.item(it) as Element }
    }

    private fun actionsOf(receiver: Element): List<String> {
        val nodes = receiver.getElementsByTagName("action")
        return (0 until nodes.length).map { (nodes.item(it) as Element).getAttribute("android:name") }
    }

    @Test
    fun `the media button receiver is declared, exported, and answers the media button`() {
        val receiver = receivers().firstOrNull {
            it.getAttribute("android:name") == "androidx.media3.session.MediaButtonReceiver"
        }

        assertNotNull("no MediaButtonReceiver, so a media key cannot resume a book after a kill", receiver)
        assertEquals("true", receiver!!.getAttribute("android:exported"))
        assertEquals(listOf("android.intent.action.MEDIA_BUTTON"), actionsOf(receiver))
    }
}
