package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.StreamingCapability
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the share browser does about one publication, driven rather than read as text.
 *
 * `SmbTransferWiringTest` reads the browser's source, and that is all a JVM gate can do to a
 * composable. It is also not enough, and the review of this change proved it: deleting the
 * judgement from `transfer` and calling `onOpen` unconditionally left
 * `StreamingOffer.of(` before `onOpen(` in the text and passed every test in the repository --
 * so the second defect this change exists to fix survived with a green suite. The decisions
 * moved into `ShareOpening.kt` so that this suite can call them with a publication of its
 * choosing and watch which callback fires.
 *
 * `StreamingOfferTest` pins the *rule*, in `:core:model`. This pins what the browser feeds it
 * and what it does with the answer. iOS asserts the same cases in `ShareOpeningTests.swift`.
 */
class ShareOpeningTest {

    /** What a callback did, so a test can assert on one thing rather than on four flags. */
    private class Answers {
        var opened: Pair<Publication, String>? = null
        var offered: Long? = null
        var offerMade = false
        var refused = false
        var failed: Int? = null
    }

    private suspend fun openingFromShare(
        publication: Publication,
        length: Long = 400_000_000L,
    ): Answers {
        val answers = Answers()
        offerOrOpen(
            index = { publication to REMOTE_PATH },
            length = length,
            onOpen = { found, path -> answers.opened = found to path },
            onOffer = { bytes -> answers.offerMade = true; answers.offered = bytes },
            onRefuse = { answers.refused = true },
            onFailure = { answers.failed = it },
        )
        return answers
    }

    private suspend fun arrivalFromShare(publication: Publication): Answers {
        val answers = Answers()
        openWhatArrived(
            fetch = { publication to LOCAL_PATH },
            onOpen = { found, path -> answers.opened = found to path },
            onRefuse = { answers.refused = true },
            onFailure = { answers.failed = it },
        )
        return answers
    }

    // --- What arrived from a completed transfer -------------------------------------------

    @Test
    fun `a solid RAR4 that has finished arriving is refused rather than opened`() = runTest {
        // The defect, exactly. A solid archive indexes as REFUSED only once its bytes are
        // local -- libarchive reads FHD_SOLID through a path -- so this is the first moment
        // the app can know, and the reader has already paid for the whole file. Opening it
        // sends them to a reader that cannot render page one.
        val answers = arrivalFromShare(publication(streaming = StreamingCapability.REFUSED))

        assertNull(
            "The publication was opened after the transfer even though no decoder will read" +
                " it. `publication-formats` asks for the refusal to be named instead.",
            answers.opened,
        )
        assertTrue("The refusal was not raised.", answers.refused)
    }

    @Test
    fun `a solid RAR5 that has finished arriving opens with no notice`() = runTest {
        // The other half of the same rule: DOWNLOAD_ONLY once local is just a book.
        // "It opens directly with no notice, because the constraint was never about the
        // format being readable."
        val answers = arrivalFromShare(
            publication(format = PublicationFormat.CBR, streaming = StreamingCapability.DOWNLOAD_ONLY),
        )

        assertEquals(LOCAL_PATH, answers.opened?.second)
        assertTrue("A downloaded solid RAR5 got a notice.", !answers.refused)
    }

    @Test
    fun `a transfer that failed is named rather than swallowed`() = runTest {
        val answers = Answers()
        openWhatArrived(
            fetch = { error("the share dropped the connection") },
            onOpen = { found, path -> answers.opened = found to path },
            onRefuse = { answers.refused = true },
            onFailure = { answers.failed = it },
        )

        assertEquals(R.string.smb_error_unexpected, answers.failed)
        assertNull(answers.opened)
    }

    // --- What was found on the share ------------------------------------------------------

    @Test
    fun `a CBZ on a share is read where it lies`() = runTest {
        // `network-share`'s whole promise: the first page of a 400 MB comic costs megabytes.
        val answers = openingFromShare(publication(format = PublicationFormat.CBZ))

        assertEquals(REMOTE_PATH, answers.opened?.second)
        assertTrue("A streamable comic was offered as a download.", !answers.offerMade)
    }

    @Test
    fun `a PDF on a share is offered with the size the share stated`() = runTest {
        // `PdfRenderer` wants a descriptor, so the whole file has to come across -- and
        // `publication-formats` asks the app to state the size and offer it, not take it.
        val answers = openingFromShare(publication(format = PublicationFormat.PDF), length = 1_050L)

        assertTrue("A PDF on a share was opened rather than offered.", answers.offerMade)
        assertEquals(1_050L, answers.offered)
        assertNull(answers.opened)
    }

    @Test
    fun `a compressed CBR on a share is offered rather than streamed`() = runTest {
        // libarchive wants a path. The container reported STREAMS, which is true of the
        // headers and not of the entries this platform can reach.
        val answers = openingFromShare(publication(format = PublicationFormat.CBR))

        assertTrue("A CBR on a share was opened rather than offered.", answers.offerMade)
    }

    @Test
    fun `a share that states no length offers an absence rather than a zero`() = runTest {
        // `offline-downloads` requires an unknown size to be stated as an absence "rather
        // than as a zero", and a directory entry's length is a non-null Long -- so a zero is
        // the only shape "the server said nothing" can arrive in. `0 B` in a download offer
        // reads as a free download.
        val answers = openingFromShare(publication(format = PublicationFormat.PDF), length = 0L)

        assertTrue("A publication needing a transfer was not offered at all.", answers.offerMade)
        assertNull("A zero-length entry was offered as a size.", answers.offered)
    }

    @Test
    fun `an index that failed over the share is named rather than swallowed`() = runTest {
        val answers = Answers()
        offerOrOpen(
            index = { error("the share dropped the connection") },
            length = 10L,
            onOpen = { found, path -> answers.opened = found to path },
            onOffer = { bytes -> answers.offerMade = true; answers.offered = bytes },
            onRefuse = { answers.refused = true },
            onFailure = { answers.failed = it },
        )

        assertEquals(R.string.smb_error_unexpected, answers.failed)
        assertTrue("A failed index still offered a transfer.", !answers.offerMade)
    }

    @Test
    fun `a remote record marked refused is offered rather than declined`() = runTest {
        // `PublicationIndexer` marks a publication it met over a share REFUSED before any
        // file exists to judge. Believing that here would decline to fetch the very
        // publication the offer is for.
        val answers = openingFromShare(
            publication(format = PublicationFormat.CBR, streaming = StreamingCapability.REFUSED),
        )

        assertTrue("A remote record marked REFUSED was declined before any file existed.", answers.offerMade)
        assertTrue(!answers.refused)
    }

    // --- The fact the rule is fed ---------------------------------------------------------

    @Test
    fun `only the formats whose decoder wants a file need one`() {
        // `publication-formats`' capability table says CBZ, CBT, EPUB, PDF and non-solid CBR
        // all stream. What is true of the *format* is not true of this platform's decoders:
        // `PdfRenderer` wants a descriptor and libarchive wants a path, and those two are the
        // whole list here. iOS's list also holds EPUB, because its reader wants a file of its
        // own.
        assertEquals(
            listOf(PublicationFormat.CBR, PublicationFormat.PDF),
            PublicationFormat.entries.filter(::needsLocalFile).sortedBy { it.name },
        )
    }

    private fun publication(
        format: PublicationFormat = PublicationFormat.CBR,
        streaming: StreamingCapability = StreamingCapability.STREAMS,
    ) = Publication(
        identity = PublicationIdentity(normalizedPath = REMOTE_PATH),
        format = format,
        displayTitle = "Solid",
        origin = MetadataOrigin.INFERRED,
        streaming = streaming,
    )

    private companion object {
        const val REMOTE_PATH = "smb://nas/comics/Solid.cbr"
        const val LOCAL_PATH = "/data/cache/smb/Solid.cbr"
    }
}
