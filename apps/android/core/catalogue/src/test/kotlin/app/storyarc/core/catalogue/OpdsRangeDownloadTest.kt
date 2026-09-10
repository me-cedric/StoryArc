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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * A download that starts again asks for the bytes it does not have, and proves they are its own.
 *
 * `offline-downloads`' *Resuming after interruption* says an interrupted download "resumes
 * from where it stopped if the server supports range requests, and restarts otherwise". Before
 * this suite there was no `Range` header anywhere in either tree, so ten changes of connection
 * on a 400 MB comic cost ten whole downloads.
 *
 * The bar is `scripts/opds-server.mjs`, which serves ranges awkwardly on purpose. Four of its
 * six deliberate misbehaviours are cases here: it answers 206 where that is right, 416 where
 * the bytes are not there, 200 with the whole body where a 206 was asked for -- which RFC 9110
 * permits -- and 200 with **only the requested window**, which is the one that cannot be told
 * from the previous case by reading the headers. Each of the last three has to end with the
 * whole publication on disk and nothing shorter.
 *
 * Every partial here is left by a first attempt this suite interrupted, rather than fabricated:
 * a resume needs the validator that attempt recorded, and a partial with none is not resumed at
 * all. Fabricating one would test a path production cannot reach.
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
    private enum class Answer {
        /** The rest of the file, as 206. */
        HONOUR,

        /** The whole file, as 200. RFC 9110 lets a server ignore a range. */
        IGNORE,

        /** Only the window, as 200. The status and the bytes disagree. */
        SLICE,

        /** 416: the bytes asked for are not there. */
        REFUSE,

        /** The whole file's length declared, half of it sent, the rest never arriving. */
        CUT,
    }

    private var answer = Answer.HONOUR

    /** What the server offers to identify this version of the file, or nothing. */
    private var validator: String? = "\"hl07-v1\""

    /** The `Range` header of the last request, or null when the request carried none. */
    private var seenRange: String? = null

    /** The `If-Range` header of the last request, or null when the request carried none. */
    private var seenIfRange: String? = null

    /** How many requests have arrived, so a restart can be told from a single ask. */
    private var requests = 0

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
        requests += 1
        seenRange = exchange.requestHeaders.getFirst("Range")
        seenIfRange = exchange.requestHeaders.getFirst("If-Range")
        val range = seenRange
        exchange.responseHeaders.add("Accept-Ranges", "bytes")
        validator?.let { exchange.responseHeaders.add("ETag", it) }
        when {
            range == null && answer == Answer.CUT -> {
                // Declared whole and sent short: the interruption every resume here starts
                // from, and the one `write` has to refuse to call a finished download.
                exchange.sendResponseHeaders(200, whole.size.toLong())
                // Flushed, then the exchange closed by hand rather than by `use`. A server
                // that declares a length and writes less of it is what an interruption is,
                // and JDK 25's `HttpServer` refuses to finish one: it throws "insufficient
                // bytes written to stream" and the reader is handed nothing at all, not even
                // the bytes already written. Flushing puts them on the wire first, so the
                // reader meets a truncated body -- `Premature EOF` -- which is the state
                // every resume here starts from. On JDK 21 the same call delivered the bytes
                // and then stalled until the client's read timeout; this is also faster.
                val body = exchange.responseBody
                body.write(whole.copyOfRange(0, CUT_AT))
                body.flush()
                exchange.close()
            }
            range == null || answer == Answer.IGNORE -> send(exchange, 200, whole)
            answer == Answer.REFUSE -> {
                exchange.responseHeaders.add("Content-Range", "bytes */${whole.size}")
                send(exchange, 416, ByteArray(0))
            }
            answer == Answer.SLICE -> send(exchange, 200, whole.copyOfRange(from(range), whole.size))
            else -> {
                val from = from(range)
                exchange.responseHeaders
                    .add("Content-Range", "bytes $from-${whole.size - 1}/${whole.size}")
                send(exchange, 206, whole.copyOfRange(from, whole.size))
            }
        }
    }

    private fun from(range: String): Int = range.removePrefix("bytes=").substringBefore('-').toInt()

    private fun send(exchange: HttpExchange, status: Int, body: ByteArray) {
        // A 416 carries no body, and `sendResponseHeaders` wants -1 rather than 0 to say so.
        exchange.sendResponseHeaders(status, if (body.isEmpty()) -1L else body.size.toLong())
        if (body.isNotEmpty()) exchange.responseBody.use { it.write(body) }
    }

    /**
     * What a first attempt left when the server stopped sending: [CUT_AT] bytes and, beside
     * them, whatever the server offered to identify the file they are a prefix of.
     *
     * The whole point of driving a real attempt rather than writing a file: the validator is
     * recorded by the attempt, and a partial without one is not resumed.
     */
    private suspend fun interrupted(): File {
        val into = File(folder.root, "hl07.cbz.part")
        answer = Answer.CUT
        runCatching { OpdsClient().download(base, into = into) }
        assertEquals("The interrupted attempt did not leave the bytes it fetched.", CUT_AT.toLong(), into.length())
        answer = Answer.HONOUR
        requests = 0
        return into
    }

    @Test
    fun `a transfer interrupted at some bytes asks for the rest of them`() = runBlocking {
        val into = interrupted()

        OpdsClient().download(base, into = into)

        assertEquals("bytes=$CUT_AT-", seenRange)
        assertArrayEquals(whole, into.readBytes())
    }

    @Test
    fun `a resumed request offers the validator the interrupted attempt recorded`() = runBlocking {
        // Without it the server cannot tell that the bytes on disk are still its own, and a
        // publication re-served after a re-scan splices onto a stale half at exactly the
        // right length.
        val into = interrupted()

        OpdsClient().download(base, into = into)

        assertEquals("\"hl07-v1\"", seenIfRange)
    }

    @Test
    fun `a partial the server offered nothing to identify is not resumed`() = runBlocking {
        validator = null
        val into = interrupted()

        OpdsClient().download(base, into = into)

        assertNull("A range was asked for with nothing to check the bytes on disk against.", seenRange)
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
            val into = interrupted()
            answer = Answer.IGNORE

            OpdsClient().download(base, into = into)

            // The trap this test exists for: CUT_AT + 4_096 bytes is a file no reader can
            // open, and a ZIP with a prefix opens far enough to look like it worked.
            assertArrayEquals(whole, into.readBytes())
        }

    @Test
    fun `a 200 carrying only the window is asked again rather than taken for the whole file`() =
        runBlocking {
            // The failure the length check cannot see: `Content-Length` describes the window,
            // the file on disk is that length, and the two agree. Landed, it is a publication
            // missing its opening bytes -- which libarchive opens as a comic with fewer pages
            // rather than refusing, so nothing downstream catches it either.
            val into = interrupted()
            answer = Answer.SLICE

            OpdsClient().download(base, into = into)

            assertArrayEquals(whole, into.readBytes())
            assertNull("The file was not asked for again without the range.", seenRange)
            assertEquals(2, requests)
        }

    @Test
    fun `a range the server cannot satisfy starts the download over`() = runBlocking {
        val into = interrupted()
        answer = Answer.REFUSE

        OpdsClient().download(base, into = into)

        assertArrayEquals(whole, into.readBytes())
    }

    @Test
    fun `a finished download leaves nothing beside it to resume from`() = runBlocking {
        val into = interrupted()

        OpdsClient().download(base, into = into)

        assertTrue(
            "The validator outlived the transfer it guarded, and the next download of this " +
                "publication would offer it for a file it knows nothing about.",
            !File(into.path + ".tag").exists(),
        )
    }

    private companion object {
        /** Where the interrupted first attempt stopped. */
        const val CUT_AT = 1_000
    }
}
