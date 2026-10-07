package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.StreamingCapability
import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the publication page does about a row whose bytes are on a share.
 *
 * Task 5.13. `SmbContributor` files a share row under the share's own `smb://` address, and the
 * page then streamed from it with nothing asked: no confirmation on a metered link, and no
 * offer for a format whose decoder wants a path, which is an open that fails rather than a
 * sentence the reader can act on.
 *
 * `ShareOpeningTest` pins the rule for the share browser's own tap. This pins the same rule
 * reached from the library, plus the one answer the browser gives before it: `network-share`'s
 * *Metered connection*, which asks for confirmation "before streaming or downloading". iOS
 * asserts the same cases in `ShareReadTests.swift`.
 */
class ShareReadTest {

    private fun row(
        format: PublicationFormat = PublicationFormat.CBZ,
        streaming: StreamingCapability = StreamingCapability.STREAMS,
        fileSize: Long? = 400_000_000L,
    ) = Publication(
        identity = PublicationIdentity(normalizedPath = SHARE),
        format = format,
        displayTitle = "Ashfall",
        origin = MetadataOrigin.INFERRED,
        streaming = streaming,
        fileSize = fileSize,
    )

    private suspend fun step(
        publication: Publication,
        isCareful: Boolean = false,
        hasConfirmedMetered: Boolean = false,
    ): ShareAsk? = shareReadStep(publication, SHARE, isCareful, hasConfirmedMetered)

    // --- Which locations are a share at all ------------------------------------------------

    @Test
    fun `a share location is told from a file by its scheme`() {
        assertTrue(isShareLocation(SHARE))
        assertFalse(isShareLocation("/comics/Ashfall.cbz"))
        assertFalse(isShareLocation("content://tree/comics/Ashfall.cbz"))
        assertFalse(
            "An acquisition URL is the download queue's, not a share's.",
            isShareLocation("https://nas/comics/Ashfall.cbz"),
        )
        assertFalse(isShareLocation(null))
    }

    // --- The metered connection ------------------------------------------------------------

    @Test
    fun `a careful link is confirmed before anything is read`() = runTest {
        // The defect this half closes: the page streamed from the share with no question
        // asked, while the share browser asked for the identical file.
        assertEquals(ShareAsk.Metered, step(row(), isCareful = true))
    }

    @Test
    fun `a confirmed careful link goes on to the offer`() = runTest {
        assertNull(step(row(), isCareful = true, hasConfirmedMetered = true))
    }

    @Test
    fun `an unmetered link is never confirmed`() = runTest {
        assertNull(step(row()))
    }

    // --- What the format owes ---------------------------------------------------------------

    @Test
    fun `a comic that streams opens where it lies`() = runTest {
        assertNull(step(row()))
    }

    @Test
    fun `a publication that cannot stream is offered with its stated size`() = runTest {
        // `publication-formats`: the app "says the format has to be downloaded before it can
        // be read, states the size, and offers to download it". A solid RAR5 is that case.
        assertEquals(
            ShareAsk.Download(400_000_000L),
            step(row(format = PublicationFormat.CBR, streaming = StreamingCapability.DOWNLOAD_ONLY)),
        )
    }

    @Test
    fun `a share that stated no length is offered with no size rather than nought`() = runTest {
        val ask = step(
            row(format = PublicationFormat.CBR, streaming = StreamingCapability.DOWNLOAD_ONLY, fileSize = null),
        )

        assertEquals(ShareAsk.Download(null), ask)
    }

    @Test
    fun `a container no decoder opens is refused rather than fetched`() = runTest {
        // A CB7 share row carries REFUSED from its name alone (`SmbContributor`), so the page
        // says so instead of offering a transfer that would change nothing.
        val ask = step(row(format = PublicationFormat.CB7, streaming = StreamingCapability.REFUSED))

        assertTrue("A refused row should be named, not opened or offered.", ask is ShareAsk.Said)
    }

    // --- The wiring the rule cannot reach ----------------------------------------------------

    @Test
    fun `the page sends a share row through the rule rather than opening it`() {
        val page = source(DETAIL_SOURCE)

        assertTrue(
            "PublicationDetailScreen opens a share row itself again. The confirmation and the" +
                " offer belong to shareReadStep, which this suite drives.",
            page.contains("reading.press(publication, where)"),
        )
        assertTrue(
            "The page draws none of the three answers, so a reader who taps a share row that" +
                " cannot stream is told nothing at all.",
            page.contains("ShareReadDialogs("),
        )
    }

    @Test
    fun `a bulk keep copies a share member in chunks rather than skipping it`() {
        val keep = source(KEEP_SOURCE)

        assertTrue(
            "keepOffline hands a share address to an InputStream again, which skips it.",
            keep.contains("PublicationAccess.remoteSource(path)"),
        )
        assertTrue(
            "The share route should copy through ChunkedCopy, as the single keep-for-offline" +
                " action does -- task 7.7's decision.",
            keep.contains("ChunkedCopy.copy(share, target)"),
        )
    }

    /**
     * A module source file, at the path this module's build script hands to the test JVM.
     *
     * The same mechanism `SmbTransferWiringTest` uses, and for the same reason: a composable
     * and a `Dispatchers.IO` copy are neither of them reachable from a JVM gate, and a guard
     * that cannot find what it guards has to say so rather than pass forever.
     */
    private fun source(relativePath: String): String {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, relativePath)
        if (!file.isFile) error("$relativePath is not under ${module.absolutePath} — has it moved?")
        return file.readText()
    }

    private companion object {
        const val SHARE = "smb://nas/comics/Ashfall.cbz"

        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val DETAIL_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/PublicationDetailScreen.kt"
        const val KEEP_SOURCE = "src/main/kotlin/app/storyarc/feature/library/KeepOffline.kt"
    }
}
