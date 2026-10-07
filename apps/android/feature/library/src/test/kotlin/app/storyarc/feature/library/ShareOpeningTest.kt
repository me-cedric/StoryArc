package app.storyarc.feature.library

import app.storyarc.core.format.IndexException
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
        var said: ShareNotice? = null
    }

    private suspend fun openingFromShare(
        publication: Publication,
        length: Long = 400_000_000L,
        name: String = "Solid.cbr",
    ): Answers {
        val answers = Answers()
        offerOrOpen(
            name = name,
            index = { publication to REMOTE_PATH },
            length = length,
            onOpen = { found, path -> answers.opened = found to path },
            onOffer = { bytes -> answers.offerMade = true; answers.offered = bytes },
            onSay = { said -> answers.said = said },
        )
        return answers
    }

    private suspend fun arrivalFromShare(publication: Publication): Answers {
        val answers = Answers()
        openWhatArrived(
            fetch = { publication to LOCAL_PATH },
            onOpen = { found, path -> answers.opened = found to path },
            onSay = { said -> answers.said = said },
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
        assertEquals(
            "The refusal `publication-formats` asks to be named was not the sentence shown.",
            ShareNotice(CANNOT_OPEN),
            answers.said,
        )
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
        assertNull("A downloaded solid RAR5 got a notice.", answers.said)
    }

    @Test
    fun `a transfer that failed is named rather than swallowed`() = runTest {
        val answers = Answers()
        openWhatArrived(
            fetch = { error("the share dropped the connection") },
            onOpen = { found, path -> answers.opened = found to path },
            onSay = { said -> answers.said = said },
        )

        assertEquals(ShareNotice(UNEXPECTED), answers.said)
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
    fun `a non-solid CBR on a share is read where it lies`() = runTest {
        // Each compressed page decodes from its own ranged bytes (`RarReader.isolated`).
        val answers = openingFromShare(publication(format = PublicationFormat.CBR))

        assertEquals(REMOTE_PATH, answers.opened?.second)
        assertTrue("A non-solid CBR was offered as a download.", !answers.offerMade)
    }

    @Test
    fun `a solid RAR5 on a share is offered with its size, not streamed`() = runTest {
        val answers = openingFromShare(
            publication(format = PublicationFormat.CBR, streaming = StreamingCapability.DOWNLOAD_ONLY),
            length = 2_048L,
        )

        assertTrue("A solid RAR5 on a share was opened rather than offered.", answers.offerMade)
        assertEquals(2_048L, answers.offered)
        assertNull(answers.opened)
    }

    @Test
    fun `only a CBR whose container said it streams reads from an address`() {
        assertTrue(readsFromAnAddress(publication(format = PublicationFormat.CBR)))
        assertTrue(
            "A solid RAR5 still arriving was offered an address it cannot be read from.",
            !readsFromAnAddress(
                publication(format = PublicationFormat.CBR, streaming = StreamingCapability.DOWNLOAD_ONLY),
            ),
        )
    }

    @Test
    fun `a reflowable EPUB on a share is offered rather than opened by its address`() = runTest {
        // `offerOrOpen` used to compute `readsWhereItLies` from `needsLocalFile(format)`
        // alone, which does not know about EPUB at all on this platform. The reader opens
        // a reflowable EPUB from a `File`, not from an `smb://` address, so this used to
        // call `onOpen` with a path `EpubReaderActivity` then failed to read.
        val answers = openingFromShare(
            publication(format = PublicationFormat.EPUB, isFixedLayout = false),
            length = 2_000L,
        )

        assertTrue("A reflowable EPUB on a share was opened by its smb:// address.", answers.offerMade)
        assertEquals(2_000L, answers.offered)
        assertNull(answers.opened)
    }

    @Test
    fun `a fixed-layout EPUB on a share is read where it lies, like a comic`() = runTest {
        val answers = openingFromShare(publication(format = PublicationFormat.EPUB, isFixedLayout = true))

        assertEquals(REMOTE_PATH, answers.opened?.second)
        assertTrue("A fixed-layout EPUB was offered as a download.", !answers.offerMade)
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
    fun `a cb7 on a share is named with its file and its format, not read as an unreachable network`() =
        runTest {
            // The indexer already names this from the headers over the share. Sending it to
            // UNEXPECTED read as "the share could not be reached" for a file the share reached
            // just fine, and the unnamed `smb_error_unsupported` named neither the file nor the
            // format -- `14.16` asks for the same file-and-format sentence Open-in already
            // shows.
            val answers = Answers()
            offerOrOpen(
                name = "Lantern Green 043.cb7",
                index = { throw IndexException.Unsupported("7-Zip") },
                length = 10L,
                onOpen = { found, path -> answers.opened = found to path },
                onOffer = { bytes -> answers.offerMade = true; answers.offered = bytes },
                onSay = { said -> answers.said = said },
            )

            assertEquals(
                ShareNotice(UNSUPPORTED, listOf("Lantern Green 043.cb7", "7-Zip")),
                answers.said,
            )
        }

    @Test
    fun `a password-protected archive on a share is named with its file, not read as an unreachable network`() =
        runTest {
            val answers = Answers()
            offerOrOpen(
                name = "Solid.cbr",
                index = { throw IndexException.ArchivePasswordProtected() },
                length = 10L,
                onOpen = { found, path -> answers.opened = found to path },
                onOffer = { bytes -> answers.offerMade = true; answers.offered = bytes },
                onSay = { said -> answers.said = said },
            )

            assertEquals(ShareNotice(PASSWORD_PROTECTED, listOf("Solid.cbr")), answers.said)
        }

    @Test
    fun `a damaged archive on a share is named with its file, not read as an unreachable network`() =
        runTest {
            val answers = Answers()
            offerOrOpen(
                name = "Solid.cbr",
                index = { throw IndexException.ArchiveUnreadable() },
                length = 10L,
                onOpen = { found, path -> answers.opened = found to path },
                onOffer = { bytes -> answers.offerMade = true; answers.offered = bytes },
                onSay = { said -> answers.said = said },
            )

            assertEquals(ShareNotice(DAMAGED, listOf("Solid.cbr")), answers.said)
        }

    @Test
    fun `an index that failed over the share is named rather than swallowed`() = runTest {
        val answers = Answers()
        offerOrOpen(
            name = "Solid.cbr",
            index = { error("the share dropped the connection") },
            length = 10L,
            onOpen = { found, path -> answers.opened = found to path },
            onOffer = { bytes -> answers.offerMade = true; answers.offered = bytes },
            onSay = { said -> answers.said = said },
        )

        assertEquals(ShareNotice(UNEXPECTED), answers.said)
        assertTrue("A failed index still offered a transfer.", !answers.offerMade)
    }

    @Test
    fun `a solid RAR4 on a share is refused before the whole file is transferred`() = runTest {
        // `RarComicArchive` detects a solid RAR4 from its headers alone, so this is no
        // longer a placeholder meaning "not checked yet" -- it is the real answer, and
        // believing it here is what stops the reader paying for a transfer that changes
        // nothing.
        val answers = openingFromShare(
            publication(format = PublicationFormat.CBR, streaming = StreamingCapability.REFUSED),
        )

        assertTrue(
            "A solid RAR4 on a share was offered a transfer instead of being refused.",
            !answers.offerMade,
        )
        assertEquals(ShareNotice(CANNOT_OPEN), answers.said)
    }

    // --- The fact the rule is fed ---------------------------------------------------------

    @Test
    fun `only the formats whose decoder wants a file need one`() {
        // `publication-formats`' capability table says CBZ, CBT, EPUB, PDF and non-solid CBR
        // all stream. What is true of the *format* is not true of this platform's decoders:
        // `PdfRenderer` wants a descriptor. A CBR is not on the list: a non-solid one decodes
        // page by page from ranged bytes. iOS's list also holds EPUB, because its reader
        // wants a file of its own.
        assertEquals(
            listOf(PublicationFormat.PDF),
            PublicationFormat.entries.filter(::needsLocalFile).sortedBy { it.name },
        )
    }

    // --- Reading while downloading, from a catalogue entry --------------------------------

    @Test
    fun `a comic acquisition reads from its catalogue address`() {
        assertTrue(catalogueReadsWhereItLies(PublicationFormat.CBZ))
    }

    @Test
    fun `a PDF, CBR or EPUB acquisition does not, because a decoder wants a file or a CBR may be solid`() {
        assertTrue(!catalogueReadsWhereItLies(PublicationFormat.PDF))
        assertTrue(!catalogueReadsWhereItLies(PublicationFormat.CBR))
        assertTrue(!catalogueReadsWhereItLies(PublicationFormat.EPUB))
    }

    @Test
    fun `an audio acquisition does not stream, even though no decoder was asked`() {
        // There is no `Publication` yet to read a `StreamingCapability` off, so this is
        // excluded on the format alone -- a player wants a file regardless of what a read of
        // the container would have said.
        assertTrue(!catalogueReadsWhereItLies(PublicationFormat.M4B))
    }

    @Test
    fun `a media type nothing recognises does not stream`() {
        assertTrue(!catalogueReadsWhereItLies(null))
    }

    private fun publication(
        format: PublicationFormat = PublicationFormat.CBR,
        streaming: StreamingCapability = StreamingCapability.STREAMS,
        isFixedLayout: Boolean = false,
    ) = Publication(
        identity = PublicationIdentity(normalizedPath = REMOTE_PATH),
        format = format,
        displayTitle = "Solid",
        origin = MetadataOrigin.INFERRED,
        streaming = streaming,
        isFixedLayout = isFixedLayout,
    )

    private companion object {
        const val REMOTE_PATH = "smb://nas/comics/Solid.cbr"
        const val LOCAL_PATH = "/data/cache/smb/Solid.cbr"
    }
}
