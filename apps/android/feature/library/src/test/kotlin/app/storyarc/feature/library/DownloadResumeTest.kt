package app.storyarc.feature.library

import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.model.PublicationFormat
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.File
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * A resumed download has to be the publication, and has to be proved to be it.
 *
 * `OpdsRangeDownloadTest` asserts what the client does with each answer a server can give a
 * `Range`. This suite asserts the consequence the reader meets: the file the queue lands is a
 * book the app opens. The queue indexes before it marks a record finished, and a resumed file
 * reaches that line by the same path a first-attempt one does -- so the check that catches a
 * truncated archive catches a badly resumed one too.
 *
 * The bytes are a real comic from the committed corpus rather than a made-up body, because the
 * failure being guarded against is subtle: a ZIP with a prefix in front of it still opens in
 * many readers, and one with its front cut off opens as a comic with fewer pages. A client that
 * appended a whole body onto partial bytes, or accepted a window as the whole file, would
 * produce a file that indexes and is not what the server holds. Every case therefore asserts
 * the bytes as well as the format.
 *
 * Each partial is left by an attempt this suite interrupted, not written by hand: the resume
 * needs the validator that attempt recorded beside it.
 *
 * `feature:library` rather than `core:catalogue`, because this is where the fetch and the
 * indexer meet. iOS resumes through the platform's own transfer instead -- a background
 * `URLSession` holds the fetched bytes where the app cannot reach them -- so it has no
 * equivalent seam.
 */
class DownloadResumeTest {

    @get:Rule
    val folder = TemporaryFolder()

    private lateinit var server: HttpServer

    /** How the server answers a `Range`, once it has one to answer. */
    private enum class Answer { HONOUR, IGNORE, SLICE, CUT }

    private var answer = Answer.HONOUR

    private val comic: ByteArray by lazy {
        File(
            requireNotNull(System.getProperty(MODULE_DIRECTORY)) {
                "$MODULE_DIRECTORY is not set — see this module's build.gradle.kts"
            },
            // apps/android/feature/library -> repository root
        ).resolve("../../../..").canonicalFile
            .resolve("packages/test-fixtures/comics/natural-sort.cbz")
            .readBytes()
    }

    private val base: String get() = "http://localhost:${server.address.port}/natural-sort.cbz"

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange -> answer(exchange) }
        server.start()
    }

    @After
    fun stop() = server.stop(0)

    private fun answer(exchange: HttpExchange) {
        val range = exchange.requestHeaders.getFirst("Range")
        exchange.responseHeaders.add("Accept-Ranges", "bytes")
        exchange.responseHeaders.add("ETag", "\"natural-sort-v1\"")
        if (range == null && answer == Answer.CUT) {
            exchange.sendResponseHeaders(200, comic.size.toLong())
            exchange.responseBody.use { it.write(comic.copyOfRange(0, CUT_AT)) }
            return
        }
        if (range == null || answer == Answer.IGNORE) {
            exchange.sendResponseHeaders(200, comic.size.toLong())
            exchange.responseBody.use { it.write(comic) }
            return
        }
        val from = range.removePrefix("bytes=").substringBefore('-').toInt()
        val slice = comic.copyOfRange(from, comic.size)
        if (answer == Answer.SLICE) {
            // The window, announced as the whole resource. Its `Content-Length` is the
            // window's, so the file this writes is exactly as long as the response says.
            exchange.sendResponseHeaders(200, slice.size.toLong())
            exchange.responseBody.use { it.write(slice) }
            return
        }
        exchange.responseHeaders.add("Content-Range", "bytes $from-${comic.size - 1}/${comic.size}")
        exchange.sendResponseHeaders(206, slice.size.toLong())
        exchange.responseBody.use { it.write(slice) }
    }

    /** What an interrupted transfer left behind: the first [CUT_AT] bytes, and the validator. */
    private suspend fun interrupted(): File {
        val into = File(folder.root, "natural-sort.cbz.part")
        answer = Answer.CUT
        runCatching { OpdsClient().download(base, into = into) }
        assertEquals(
            "The interrupted attempt did not leave the bytes it fetched.",
            CUT_AT.toLong(),
            into.length(),
        )
        answer = Answer.HONOUR
        return into
    }

    @Test
    fun `a resumed download indexes as the publication it is`() = runBlocking {
        val file = interrupted()

        OpdsClient().download(base, into = file)

        assertArrayEquals("A resumed download is not the file the server holds.", comic, file.readBytes())
        assertEquals(PublicationFormat.CBZ, PublicationIndexer.index(file).format)
    }

    @Test
    fun `a server that ignores the range lands the publication rather than a longer file`() =
        runBlocking {
            val file = interrupted()
            answer = Answer.IGNORE

            OpdsClient().download(base, into = file)

            assertEquals(
                "The partial bytes were kept, so the file is longer than the publication.",
                comic.size.toLong(),
                file.length(),
            )
            assertArrayEquals(comic, file.readBytes())
            assertEquals(PublicationFormat.CBZ, PublicationIndexer.index(file).format)
        }

    @Test
    fun `a window announced as the whole file lands the publication rather than a shorter one`() =
        runBlocking {
            // The one the indexer cannot catch. A CBZ with its front cut off is scanned
            // forward to the first intact entry and opens as a comic with fewer pages, so a
            // reader is told a 400 MB book is available offline and meets it without its
            // opening pages. Refused at the fetch or not at all.
            val file = interrupted()
            answer = Answer.SLICE

            OpdsClient().download(base, into = file)

            assertEquals(
                "A window was taken for the whole file, so the publication is missing its front.",
                comic.size.toLong(),
                file.length(),
            )
            assertArrayEquals(comic, file.readBytes())
            assertEquals(PublicationFormat.CBZ, PublicationIndexer.index(file).format)
        }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"

        /** Where the interrupted first attempt stopped. */
        const val CUT_AT = 500
    }
}
