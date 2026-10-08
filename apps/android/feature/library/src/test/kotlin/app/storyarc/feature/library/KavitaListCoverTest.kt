package app.storyarc.feature.library

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.format.CoverOverrideStore
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaReadingList
import app.storyarc.core.model.CoverWriteSubject
import com.sun.net.httpserver.HttpServer
import java.io.ByteArrayOutputStream
import java.net.InetSocketAddress
import java.util.Base64
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Tasks 6.4 and 5.1 of `cover-for-every-publication`: the write-back button is on the Kavita
 * reading-list screen, once a cover is chosen, and never on a list that is not the reader's.
 *
 * The first four tests state the rules on their own. The rest open the real
 * [KavitaListScreen] against a local server, because a button that is placed on no screen
 * passes every test that never opens one. iOS's `KavitaListCoverTests` is the twin.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class KavitaListCoverTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private var server: HttpServer? = null
    private val source = UUID.randomUUID().toString()

    private val owned = KavitaReadingList(id = 8, title = "Crossover", promoted = false)
    private val promoted = KavitaReadingList(id = 8, title = "Crossover", promoted = true)

    @After
    fun stop() {
        server?.stop(0)
    }

    // The rules, on their own.

    @Test
    fun `no button without a chosen cover`() {
        assertNull(KavitaListCover.writeSubject(8, hasChosen = false, lists = listOf(owned)))
    }

    @Test
    fun `an owned list with a chosen cover asks the button`() {
        assertEquals(
            CoverWriteSubject.KavitaReadingList(8, promoted = false),
            KavitaListCover.writeSubject(8, hasChosen = true, lists = listOf(owned)),
        )
    }

    @Test
    fun `a promoted list is handed to the one rule that refuses it`() {
        val subject = KavitaListCover.writeSubject(8, hasChosen = true, lists = listOf(promoted))

        assertEquals(CoverWriteSubject.KavitaReadingList(8, promoted = true), subject)
        assertEquals(
            app.storyarc.core.model.CoverWriteOffer.None,
            app.storyarc.core.model.CoverWriteBack.offer(subject!!),
        )
    }

    @Test
    fun `ownership the server never stated proves nothing`() {
        assertNull(KavitaListCover.writeSubject(8, hasChosen = true, lists = null))
        assertNull(KavitaListCover.writeSubject(8, hasChosen = true, lists = listOf(owned.copy(id = 9))))
    }

    // The screen.

    private fun png(): ByteArray = ByteArrayOutputStream().also {
        Bitmap.createBitmap(8, 12, Bitmap.Config.ARGB_8888).compress(Bitmap.CompressFormat.PNG, 100, it)
    }.toByteArray()

    /** Files a cover as the reader's own for list 8, the way choosing one does. */
    private fun chooseCover(): ByteArray {
        val picture = png()
        val list = requireNotNull(KavitaListCover.publication(source, 8))
        CoverOverrideStore(CoverOverrideStore.directoryIn(context.filesDir)).store(picture, list)
        return picture
    }

    private var uploaded: String? = null

    /** Set once the server has written its answer to the list's own listing. */
    @Volatile
    private var listsAnswered = false

    private fun serve(lists: String) {
        val started = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        started.createContext("/") { exchange ->
            val path = exchange.requestURI.path
            if (path.endsWith("/Upload/reading-list")) uploaded = exchange.requestBody.readBytes().decodeToString()
            val body = when {
                path.endsWith("/Plugin/authenticate") -> """{"username":"ada","token":"t"}"""
                path.endsWith("/ReadingList/lists") -> lists
                path.endsWith("/ReadingList/items") -> "[]"
                path.endsWith("/Upload/reading-list") -> "{}"
                else -> null
            }?.toByteArray()
            exchange.sendResponseHeaders(if (body == null) 404 else 200, body?.size?.toLong() ?: -1)
            exchange.responseBody.use { stream -> body?.let(stream::write) }
            if (path.endsWith("/ReadingList/lists")) listsAnswered = true
        }
        started.start()
        server = started
    }

    private fun show() {
        val page = KavitaPage(source, "Attic", KavitaAddress("http://localhost:${server!!.address.port}", "key"))
        compose.setContent {
            StoryArcTheme {
                KavitaListScreen(server = page, listId = 8, title = "Crossover", onOpen = { _, _ -> }, onBack = {})
            }
        }
        compose.waitForIdle()
    }

    private val send get() = context.getString(R.string.covers_write_back)

    /** Waits until the listing was answered and the screen has had time to take it. */
    private fun waitForTheListing() {
        compose.waitUntil(10_000) { listsAnswered }
        Thread.sleep(500)
        compose.waitForIdle()
    }

    private fun present(text: String) = compose.onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty()

    /** The cover's one menu, opened from its edit button. */
    private fun openMenu() {
        compose.onNodeWithContentDescription(context.getString(R.string.cover_edit)).performClick()
    }

    private val store get() = CoverOverrideStore(CoverOverrideStore.directoryIn(context.filesDir))

    @Test
    fun `the button is on the screen of a list the reader owns once a cover is chosen`() {
        chooseCover()
        serve("""[{"id":8,"title":"Crossover","promoted":false}]""")

        show()
        openMenu()
        compose.waitUntil(10_000) { present(send) }
    }

    @Test
    fun `no button on the screen before a cover is chosen, and the screen offers the choice`() {
        serve("""[{"id":8,"title":"Crossover","promoted":false}]""")

        show()
        compose.waitUntil(10_000) { present(context.getString(R.string.cover_add)) }
        waitForTheListing()
        openMenu()

        assertEquals(true, present(context.getString(R.string.cover_pick)))
        assertEquals(false, present(send))
    }

    @Test
    fun `no button on the screen of a promoted list, whatever the reader chose`() {
        chooseCover()
        serve("""[{"id":8,"title":"Crossover","promoted":true}]""")

        show()
        openMenu()
        compose.waitUntil(10_000) { present(context.getString(R.string.cover_remove)) }
        waitForTheListing()

        assertEquals(false, present(send))
    }

    @Test
    fun `a confirmed send posts the chosen picture to the list it was chosen for`() {
        val picture = chooseCover()
        serve("""[{"id":8,"title":"Crossover","promoted":false}]""")
        show()
        openMenu()
        compose.waitUntil(10_000) { present(send) }

        compose.onNodeWithText(send).performClick()
        compose.onNodeWithText(context.getString(R.string.covers_write_back_send)).performClick()
        compose.waitUntil(10_000) { uploaded != null }

        val body = kotlinx.serialization.json.Json.parseToJsonElement(uploaded!!)
            as kotlinx.serialization.json.JsonObject
        assertEquals("8", body["id"].toString())
        val sent = Base64.getDecoder().decode((body["url"] as kotlinx.serialization.json.JsonPrimitive).content)
        assertNotNull(sent)
        assertArrayEquals(picture, sent)
    }

    @Test
    fun `removing a chosen cover asks first, and dismissing the question keeps the picture`() {
        val picture = chooseCover()
        serve("""[{"id":8,"title":"Crossover","promoted":false}]""")
        show()
        val remove = context.getString(R.string.cover_remove)
        val list = requireNotNull(KavitaListCover.publication(source, 8))

        openMenu()
        compose.waitUntil(10_000) { present(remove) }
        compose.onNodeWithText(remove).performClick()

        compose.onNodeWithText(context.getString(R.string.cover_remove_title)).assertExists()
        assertArrayEquals("the row deleted the picture before asking", picture, store.bytes(list))
        compose.onNodeWithText(context.getString(R.string.shelves_cancel)).performClick()
        compose.waitForIdle()

        compose.onNodeWithText(context.getString(R.string.cover_remove_title)).assertDoesNotExist()
        assertArrayEquals("dismissing the question deleted the picture", picture, store.bytes(list))

        openMenu()
        compose.onNodeWithText(remove).performClick()
        compose.onNodeWithText(remove).performClick()
        compose.waitUntil(10_000) { store.bytes(list) == null }
    }
}
