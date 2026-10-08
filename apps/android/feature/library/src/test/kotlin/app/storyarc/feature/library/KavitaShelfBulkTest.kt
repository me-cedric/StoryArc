package app.storyarc.feature.library

import android.content.Context
import android.text.format.Formatter
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaChapterFile
import app.storyarc.core.kavita.KavitaReadingListItem
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.kavita.KavitaVolume
import app.storyarc.core.model.AppSettings
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.KavitaCardStore
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Task 7.8 of `close-the-audited-gaps`: a server's collection or reading list is downloaded and
 * marked read as a whole, with its count and size stated first and a ten-second undo on the mark.
 *
 * The first tests state the rules on their own. The last two open the real [KavitaListScreen]
 * against a local server, because a menu placed on no screen passes every test that never opens
 * one. iOS's `KavitaShelfBulkTests` is the twin of this file.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class KavitaShelfBulkTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private var server: HttpServer? = null
    private val source = UUID.randomUUID().toString()

    @After
    fun stop() {
        server?.stop(0)
    }

    private fun entry(chapter: Int, series: Int, read: Int, size: Long) = KavitaReadingListItem(
        id = chapter, order = chapter, seriesId = series, chapterId = chapter, title = "Issue #$chapter",
        seriesName = "Lantern", pagesRead = read, pagesTotal = 20, volumeId = series * 100,
        libraryId = 2, fileSize = size,
    )

    private val items = listOf(entry(11, 1, 0, 1_000), entry(12, 1, 5, 2_000), entry(13, 1, 20, 3_000))

    // The rules, on their own.

    @Test
    fun `the count stated is the count of chapters not already on the device`() {
        val ask = KavitaShelfBulk.downloadAsk(KavitaShelfBulk.chaptersOf(items), kept = setOf(11))

        assertEquals(2, ask?.count)
        assertEquals(listOf(12, 13), ask?.chapters?.map { it.chapter.id })
    }

    @Test
    fun `everything already kept states nothing to ask`() {
        assertNull(KavitaShelfBulk.downloadAsk(KavitaShelfBulk.chaptersOf(items), kept = setOf(11, 12, 13)))
    }

    @Test
    fun `the size is the sum when every chapter states one, a floor when some do not, and none when none do`() {
        val chapters = KavitaShelfBulk.chaptersOf(items)

        assertEquals(KavitaBulkSize.Known(6_000), KavitaShelfBulk.downloadAsk(chapters, emptySet())?.size)
        val partial = KavitaShelfBulk.chaptersOf(listOf(entry(11, 1, 0, 1_000), entry(12, 1, 0, 0)))
        assertEquals(KavitaBulkSize.AtLeast(1_000), KavitaShelfBulk.downloadAsk(partial, emptySet())?.size)
        val unstated = KavitaShelfBulk.chaptersOf(listOf(entry(11, 1, 0, 0)))
        assertEquals(KavitaBulkSize.Unstated, KavitaShelfBulk.downloadAsk(unstated, emptySet())?.size)
    }

    @Test
    fun `the chapters queued are exactly the chapters the reader was told about`() = runBlocking {
        val ask = requireNotNull(
            KavitaShelfBulk.downloadAsk(KavitaShelfBulk.chaptersOf(items), kept = setOf(12)),
        )
        val queued = CopyOnWriteArrayList<Int>()

        val kept = KavitaShelfBulk.download(ask) { each -> queued += each.chapter.id; true }

        assertEquals(ask.count, queued.size)
        assertEquals(ask.chapters.map { it.chapter.id }.sorted(), queued.sorted())
        assertEquals(ask.count, kept)
    }

    @Test
    fun `a mark changes only the chapters not already in that state, and the undo is those same chapters`() =
        runBlocking {
            val chapters = KavitaShelfBulk.chaptersOf(items)
            val moving = KavitaShelfBulk.changing(chapters, read = true)
            val sent = mutableListOf<Pair<Int, Boolean>>()

            KavitaShelfBulk.mark(moving, read = true) { each, read -> sent += each.chapter.id to read }
            val undo = KavitaMarkUndo(moving, read = true)
            KavitaShelfBulk.mark(undo.chapters, !undo.read) { each, read -> sent += each.chapter.id to read }

            assertEquals(
                listOf(11 to true, 12 to true, 11 to false, 12 to false),
                sent,
            )
        }

    @Test
    fun `a collection holds the chapters of its series, and a series the server cannot read makes it unreadable`() =
        runBlocking {
            val series = listOf(KavitaSeries(id = 1, name = "Lantern"), KavitaSeries(id = 2, name = "Harbour"))
            val volumes = mapOf(
                1 to listOf(KavitaVolume(id = 100, chapters = listOf(KavitaChapter(id = 11, pages = 20)))),
                2 to listOf(
                    KavitaVolume(
                        id = 200,
                        chapters = listOf(KavitaChapter(id = 21, files = listOf(KavitaChapterFile(500)))),
                    ),
                ),
            )

            val whole = KavitaShelfBulk.chaptersOf(series) { volumes.getValue(it) }
            val broken = KavitaShelfBulk.chaptersOf(series) { id ->
                if (id == 2) error("the server did not answer") else volumes.getValue(id)
            }

            assertEquals(listOf(11, 21), whole?.map { it.chapter.id })
            assertEquals(500L, whole?.last()?.bytes)
            assertNull("a count over part of a collection was stated", broken)
        }

    // The screen.

    private val marks = CopyOnWriteArrayList<String>()

    private fun serve() {
        val started = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        started.createContext("/") { exchange ->
            val path = exchange.requestURI.path
            val sent = exchange.requestBody.readBytes().decodeToString()
            if (path.contains("/Reader/mark-")) marks += path.substringAfterLast('/') + " " + sent
            val body = when {
                path.endsWith("/Plugin/authenticate") -> """{"username":"ada","token":"t"}"""
                path.endsWith("/ReadingList/items") -> kotlinx.serialization.json.Json.encodeToString(
                    kotlinx.serialization.builtins.ListSerializer(KavitaReadingListItem.serializer()), items,
                )
                path.contains("/Reader/mark-") -> "{}"
                path.endsWith("/ReadingList/lists") -> "[]"
                else -> null
            }?.toByteArray()
            exchange.sendResponseHeaders(if (body == null) 500 else 200, body?.size?.toLong() ?: -1)
            exchange.responseBody.use { stream -> body?.let(stream::write) }
        }
        started.start()
        server = started
    }

    private fun queue() = DownloadQueue(
        context,
        CertificatePins(),
        DownloadStore.open(context),
        settings = { AppSettings(downloadOverWifiOnly = false) },
        onWifi = MutableStateFlow(true),
    )

    private fun show(queue: DownloadQueue?) {
        val page = KavitaPage(source, "Attic", KavitaAddress("http://localhost:${server!!.address.port}", "key"))
        compose.setContent {
            StoryArcTheme {
                KavitaListScreen(
                    server = page, listId = 8, title = "Crossover", onOpen = { _, _ -> }, onBack = {},
                    queue = queue,
                )
            }
        }
        compose.waitUntil(10_000) { present("Issue #11") }
    }

    private fun present(text: String) = compose.onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty()

    private fun openMenu() {
        compose.onNodeWithContentDescription(context.getString(R.string.shelves_bulk)).performClick()
    }

    @Test
    fun `the download states the count and the size, and a confirmed one queues exactly that many`() {
        serve()
        // Chapter 11 is already on the device, so the reader is told about two and two are queued.
        KavitaCardStore.open(context).save(
            KavitaKeep.card(
                publicationId = "kept-11", downloadId = "kavita:$source:11",
                chapter = KavitaChapter(id = 11), series = KavitaSeries(id = 1, name = "Lantern"),
                metadata = null,
                origin = KavitaShelfBulk.chaptersOf(items).first().origin(source),
            ),
        )
        val queue = queue()
        show(queue)

        openMenu()
        compose.onNodeWithText(context.getString(R.string.library_bulk_download)).performClick()
        compose.waitUntil(10_000) { present(context.resources.getQuantityString(R.plurals.library_bulk_download_title, 2, 2)) }
        assertTrue(present(context.getString(R.string.library_bulk_download_size, Formatter.formatFileSize(context, 5_000))))

        // The menu has closed, so the only "Download" left is the dialog's own button.
        compose.onNodeWithText(context.getString(R.string.library_bulk_download)).performClick()

        compose.waitUntil(10_000) { queue.library.value.downloads.size >= 2 }
        assertEquals(
            setOf("kavita:$source:12", "kavita:$source:13"),
            queue.library.value.downloads.map { it.id }.toSet(),
        )
        assertNotNull(queue.library.value["kavita:$source:12"])
    }

    @Test
    fun `a whole-shelf mark sends one mark per unread chapter, and the undo takes those back`() {
        serve()
        show(queue = null)

        openMenu()
        compose.onNodeWithText(context.getString(R.string.library_mark_read)).performClick()
        compose.waitUntil(10_000) { marks.count { it.startsWith("mark-multiple-read") } == 2 }
        val read = marks.filter { it.startsWith("mark-multiple-read") }
        assertTrue(read.any { "\"chapterIds\":[11]" in it })
        assertTrue(read.any { "\"chapterIds\":[12]" in it })
        assertTrue("the finished chapter was marked again", read.none { "13" in it.substringAfter("chapterIds") })

        compose.waitUntil(10_000) { present(context.resources.getQuantityString(R.plurals.library_bulk_changed, 2, 2)) }
        compose.onNodeWithText(context.getString(R.string.downloads_undo)).performClick()
        compose.waitUntil(10_000) { marks.count { it.startsWith("mark-multiple-unread") } == 2 }
        val unread = marks.filter { it.startsWith("mark-multiple-unread") }
        assertTrue(unread.any { "\"chapterIds\":[11]" in it })
        assertTrue(unread.any { "\"chapterIds\":[12]" in it })
    }
}
