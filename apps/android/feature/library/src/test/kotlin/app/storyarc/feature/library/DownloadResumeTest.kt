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
 * `OpdsRangeDownloadTest` asserts what the client does with each of the three answers a server
 * can give a `Range`. This suite asserts the consequence the reader meets: the file the queue
 * lands is a book the app opens. The queue indexes before it marks a record finished, and a
 * resumed file reaches that line by the same path a first-attempt one does -- so the check that
 * catches a truncated archive catches a badly resumed one too.
 *
 * The bytes are a real comic from the committed corpus rather than a made-up body, because the
 * failure being guarded against is subtle: a ZIP with a prefix in front of it still opens in
 * many readers, so a client that appended a whole body onto partial bytes would produce a file
 * that indexes and is not what the server holds. Both cases therefore assert the bytes as well
 * as the format.
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

    /** Whether the server honours a `Range` or ignores it, which RFC 9110 lets it do. */
    private var honoursRange = true

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
        if (range == null || !honoursRange) {
            exchange.sendResponseHeaders(200, comic.size.toLong())
            exchange.responseBody.use { it.write(comic) }
            return
        }
        val from = range.removePrefix("bytes=").substringBefore('-').toInt()
        val slice = comic.copyOfRange(from, comic.size)
        exchange.responseHeaders.add("Content-Range", "bytes $from-${comic.size - 1}/${comic.size}")
        exchange.sendResponseHeaders(206, slice.size.toLong())
        exchange.responseBody.use { it.write(slice) }
    }

    /** What an interrupted transfer left behind: the first [bytes] bytes of the comic. */
    private fun interrupted(bytes: Int): File =
        folder.newFile("natural-sort.cbz").apply { writeBytes(comic.copyOfRange(0, bytes)) }

    @Test
    fun `a resumed download indexes as the publication it is`() = runBlocking {
        val file = interrupted(500)

        OpdsClient().download(base, into = file)

        assertArrayEquals("A resumed download is not the file the server holds.", comic, file.readBytes())
        assertEquals(PublicationFormat.CBZ, PublicationIndexer.index(file).format)
    }

    @Test
    fun `a server that ignores the range lands the publication rather than a longer file`() =
        runBlocking {
            honoursRange = false
            val file = interrupted(500)

            OpdsClient().download(base, into = file)

            assertEquals(
                "The partial bytes were kept, so the file is longer than the publication.",
                comic.size.toLong(),
                file.length(),
            )
            assertArrayEquals(comic, file.readBytes())
            assertEquals(PublicationFormat.CBZ, PublicationIndexer.index(file).format)
        }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
    }
}
