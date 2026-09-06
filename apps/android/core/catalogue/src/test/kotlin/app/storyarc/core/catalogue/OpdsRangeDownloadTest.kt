package app.storyarc.core.catalogue

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.io.File
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * A download that starts again asks for the bytes it does not have.
 *
 * `offline-downloads`' *Resuming after interruption* says an interrupted download "resumes
 * from where it stopped if the server supports range requests, and restarts otherwise". Before
 * this suite there was no `Range` header anywhere in either tree, so ten changes of connection
 * on a 400 MB comic cost ten whole downloads.
 *
 * The bar is `scripts/opds-server.mjs`, which serves ranges awkwardly on purpose: it answers
 * 206 where that is right, 416 where the bytes are not there, and -- legally -- 200 with the
 * whole body where a 206 was asked for. A client that appends a whole body onto partial bytes
 * writes a file that is not the publication, so each of the three answers is a case here.
 *
 * A live server on the loopback interface rather than a stubbed connection, for the reason
 * [OpdsClientTest] gives: the status and the header are decisions `HttpURLConnection` makes as
 * much as this code does. iOS resumes through the platform's own transfer instead, because a
 * background `URLSession` holds the fetched bytes where the app cannot reach them.
 */
class OpdsRangeDownloadTest {

    @get:Rule
    val folder = TemporaryFolder()

    private lateinit var server: HttpServer

    /** What the server holds. Long enough that a prefix of it is not the whole of it. */
    private val whole = ByteArray(4_096) { (it % 251).toByte() }

    /** How the server answers a `Range` it is given. */
    private enum class Answer { HONOUR, IGNORE, REFUSE }

    private var answer = Answer.HONOUR

    /** The `Range` header of the last request, or null when the request carried none. */
    private var seenRange: String? = null

    private val base: String get() = "http://localhost:${server.address.port}/hl07.cbz"

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange -> answer(exchange) }
        server.start()
    }

    @After
    fun stop() = server.stop(0)

    private fun answer(exchange: HttpExchange) {
        seenRange = exchange.requestHeaders.getFirst("Range")
        val range = seenRange
        exchange.responseHeaders.add("Accept-Ranges", "bytes")
        when {
            range == null || answer == Answer.IGNORE -> send(exchange, 200, whole)
            answer == Answer.REFUSE -> {
                exchange.responseHeaders.add("Content-Range", "bytes */${whole.size}")
                send(exchange, 416, ByteArray(0))
            }
            else -> {
                val from = range.removePrefix("bytes=").substringBefore('-').toInt()
                val slice = whole.copyOfRange(from, whole.size)
                exchange.responseHeaders
                    .add("Content-Range", "bytes $from-${whole.size - 1}/${whole.size}")
                send(exchange, 206, slice)
            }
        }
    }

    private fun send(exchange: HttpExchange, status: Int, body: ByteArray) {
        // A 416 carries no body, and `sendResponseHeaders` wants -1 rather than 0 to say so.
        exchange.sendResponseHeaders(status, if (body.isEmpty()) -1L else body.size.toLong())
        if (body.isNotEmpty()) exchange.responseBody.use { it.write(body) }
    }

    /**
     * A partial file of [bytes] bytes.
     *
     * A prefix of what the server holds while it is shorter than that, and bytes of its own
     * beyond it -- a file longer than the resource is how a range becomes unsatisfiable.
     */
    private fun partial(bytes: Int): File = folder.newFile("hl07.cbz.part").apply {
        writeBytes(ByteArray(bytes) { if (it < whole.size) whole[it] else 0 })
    }

    @Test
    fun `a transfer interrupted at some bytes asks for the rest of them`() = runBlocking {
        val into = partial(1_000)

        OpdsClient().download(base, into = into)

        assertEquals("bytes=1000-", seenRange)
        assertArrayEquals(whole, into.readBytes())
    }

    @Test
    fun `a first attempt asks for no range at all`() = runBlocking {
        val into = File(folder.root, "hl07.cbz.part")

        OpdsClient().download(base, into = into)

        assertNull(seenRange)
        assertArrayEquals(whole, into.readBytes())
    }

    @Test
    fun `a server that ignores the range replaces the partial instead of appending to it`() =
        runBlocking {
            answer = Answer.IGNORE
            val into = partial(1_000)

            OpdsClient().download(base, into = into)

            // The trap this test exists for: 1_000 + 4_096 bytes is a file no reader can open,
            // and a ZIP with a prefix opens far enough to look like it worked.
            assertArrayEquals(whole, into.readBytes())
        }

    @Test
    fun `a range the server cannot satisfy starts the download over`() = runBlocking {
        answer = Answer.REFUSE
        val into = partial(9_000)

        OpdsClient().download(base, into = into)

        assertArrayEquals(whole, into.readBytes())
    }
}
