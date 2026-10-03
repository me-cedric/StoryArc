package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.nio.file.Files
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeNoException
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

/**
 * The app's own Kavita client, driven against the real `scripts/kavita-server.mjs` rather
 * than a stub.
 *
 * Package `f4-read-core`, task 22.1's own corrected scope, item 3: "No automated test runs
 * the app's own Kavita client against the mock." Every other `KavitaContributor` test answers
 * its requests itself, through `com.sun.net.httpserver.HttpServer` -- proof that this code
 * decodes the shape it is given, and no proof at all that the shape it is given is the shape
 * the mock actually sends. This spawns the real script, on a free port of its own, and reads
 * past the first slice with it -- the walk the corrected scope asks for.
 *
 * Skipped, not failed, when `node` is not on the path this run has -- the same courtesy
 * `SmbClientTest` extends a checkout without its own fixture server running.
 */
class KavitaContributorAgainstTheMockTest {

    private var process: Process? = null
    private lateinit var corpus: File

    /** More series than [KavitaContributor.FIRST_SLICE] holds, so a second page has something in it. */
    private val seriesCount = KavitaContributor.FIRST_SLICE + 10

    /** This module's own directory, the same system property `KavitaOpenFailureTest` reads. */
    private val repoRoot: File
        get() = File(
            requireNotNull(System.getProperty("storyarc.library.projectDir")) {
                "storyarc.library.projectDir is not set -- see this module's build.gradle.kts"
            },
        ).resolve("../../../..").canonicalFile

    @Before
    fun start() {
        // A scratch corpus rather than the committed fixtures: what this test needs is a
        // count past the first slice, and `scripts/kavita-server.mjs` groups a series by its
        // file name alone -- so a name with no space before its digits is its own series,
        // the same device `--self-test`'s own scratch corpus uses for the same reason.
        corpus = Files.createTempDirectory("storyarc-kavita-mock-").toFile()
        repeat(seriesCount) { index ->
            File(corpus, "BulkSeries${index.toString().padStart(4, '0')}.cbz")
                .writeBytes("not a real publication".toByteArray())
        }
    }

    @After
    fun stop() {
        process?.destroy()
        corpus.deleteRecursively()
    }

    /** The port the mock actually bound, once its own banner line says so, or null if it never did. */
    private fun startServer(): Int? {
        val script = repoRoot.resolve("scripts/kavita-server.mjs")
        val started = runCatching {
            ProcessBuilder("node", script.absolutePath, corpus.absolutePath, "--port", "0")
                .redirectErrorStream(true)
                .start()
        }
        assumeNoException("node must be on PATH to drive the real mock", started.exceptionOrNull())
        val server = started.getOrThrow()
        process = server
        val reader = BufferedReader(InputStreamReader(server.inputStream))
        val pattern = Regex("""kavita mock: http://localhost:(\d+)""")
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            val line = reader.readLine() ?: break
            pattern.find(line)?.let { return it.groupValues[1].toInt() }
        }
        return null
    }

    @Test
    fun `the real mock answers past the first slice, through the app's own client`() = runBlocking {
        val port = startServer()
        assumeTrue("the mock did not print its banner in time", port != null)

        val client = KavitaClient(KavitaAddress("http://localhost:$port", "storyarc-test-key"))
        val source = UUID.randomUUID()

        val first = KavitaContributor.page(source, client, page = 1)
        assertEquals(KavitaContributor.FIRST_SLICE, first.seriesRead)
        assertTrue("a corpus of $seriesCount series fills the first slice", first.slice.holdsMore)

        val second = KavitaContributor.page(source, client, page = 2)
        assertTrue("page two is reached, which is reading past the first slice", second.seriesRead > 0)
        assertEquals(seriesCount - KavitaContributor.FIRST_SLICE, second.seriesRead)
        assertFalse("ten more series than the first slice is a short, final page", second.slice.holdsMore)
    }
}
