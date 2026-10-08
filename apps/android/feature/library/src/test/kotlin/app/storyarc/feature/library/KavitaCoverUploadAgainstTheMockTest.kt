package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaError
import app.storyarc.core.kavita.uploadReadingListCover
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.nio.file.Files
import java.util.Base64
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeNoException
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

/**
 * The app's own cover upload, driven against the real `scripts/kavita-server.mjs`.
 *
 * Task 5.3 of `cover-for-every-publication`. The shape of `Upload/reading-list` came from
 * documentation, and every other test of it answers its own requests, which proves this code
 * sends what it means to and nothing about what a server does with it. This spawns the mock,
 * sends a picture through [uploadReadingListCover], and asks the list's own cover route for it
 * back. The mock decodes the base64 and refuses what a real server would, so the bytes that
 * come back are the bytes that were chosen.
 *
 * It proves the client against the mock and nothing more. A real Kavita is the owner's
 * check, and the device checklist carries it.
 *
 * The same mock answers the sizes task 7.8 reads: a list entry's `fileSize` and a chapter's
 * `files[].bytes`, so a whole-shelf download can state its size before it starts.
 *
 * Skipped, not failed, when `node` is not on the path of this run.
 */
class KavitaCoverUploadAgainstTheMockTest {

    private var process: Process? = null
    private lateinit var corpus: File

    /** A 1 x 1 PNG: the mock reads the type from the first bytes and keeps the rest whole. */
    private val picture = Base64.getDecoder().decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
    )

    @Before
    fun start() {
        corpus = Files.createTempDirectory("storyarc-kavita-upload-").toFile()
        File(corpus, "Tidal Reach 01.cbz").writeBytes("not a real publication".toByteArray())
    }

    @After
    fun stop() {
        process?.destroy()
        corpus.deleteRecursively()
    }

    private fun startServer(): KavitaClient? {
        val root = File(
            requireNotNull(System.getProperty("storyarc.library.projectDir")) {
                "storyarc.library.projectDir is not set -- see this module's build.gradle.kts"
            },
        ).resolve("../../../..").canonicalFile
        val started = runCatching {
            ProcessBuilder(
                "node", root.resolve("scripts/kavita-server.mjs").absolutePath, corpus.absolutePath,
                "--port", "0",
            ).redirectErrorStream(true).start()
        }
        assumeNoException("node must be on PATH to drive the real mock", started.exceptionOrNull())
        val server = started.getOrThrow()
        process = server
        val reader = BufferedReader(InputStreamReader(server.inputStream))
        val pattern = Regex("""kavita mock: http://localhost:(\d+)""")
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            val line = reader.readLine() ?: break
            pattern.find(line)?.let {
                return KavitaClient(KavitaAddress("http://localhost:${it.groupValues[1]}", "storyarc-test-key"))
            }
        }
        return null
    }

    @Test
    fun `a chosen cover is served back byte for byte and the list says it is locked`() = runBlocking {
        val client = startServer()
        assumeTrue("the mock did not print its banner in time", client != null)
        client!!
        assertFalse(
            "the list was locked before anything was sent",
            client.readingLists().first { it.id == 1 }.coverImageLocked,
        )

        client.uploadReadingListCover(1, picture)

        assertArrayEquals(picture, client.readingListCover(1))
        assertTrue(client.readingLists().first { it.id == 1 }.coverImageLocked)
        assertFalse("the mock calls a list nobody promoted promoted", client.readingLists().first().promoted)
    }

    @Test
    fun `bytes that are not a picture are refused and the earlier cover stays`() = runBlocking {
        val client = startServer()
        assumeTrue("the mock did not print its banner in time", client != null)
        client!!
        client.uploadReadingListCover(1, picture)

        try {
            client.uploadReadingListCover(1, "plain text, not an image".toByteArray())
            fail("the mock accepted bytes that are not an image")
        } catch (refused: KavitaError.Http) {
            assertEquals(400, refused.status)
        }

        assertArrayEquals(picture, client.readingListCover(1))
    }

    @Test
    fun `a list entry and a chapter state the size of their file`() = runBlocking {
        val client = startServer()
        assumeTrue("the mock did not print its banner in time", client != null)
        client!!

        val first = client.readingListItems(1).first()
        // The corpus file holds 22 bytes, which is what the mock must state for it.
        assertEquals(22L, first.fileSize)
        assertTrue(first.pagesTotal > 0 && first.volumeId > 0 && first.libraryId > 0)
        val chapters = client.volumes(first.seriesId).flatMap { it.chapters }
        assertTrue(chapters.isNotEmpty())
        assertTrue(chapters.all { it.sizeBytes == 22L })
    }
}
