package app.storyarc.feature.library

import app.storyarc.core.model.Download
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingAddress
import app.storyarc.core.model.StreamingCapability
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The two rules a publication's page puts together to answer `offline-downloads`' *Reading
 * while downloading*, composed the way the page composes them.
 *
 * [ReadingAddress] says *where*, and [primaryActionOf] says *what the button offers*. Each is
 * asserted on its own -- `ReadingAddressTest` in `:core:model`, `DetailActionsTest` here --
 * and neither on its own says what this scenario is about. The defect they miss between them
 * is the one this repository shipped: an address that exists and a button that still says
 * Download.
 *
 * iOS reaches the same pair through `ReadingAddressTests`; its publication page has no
 * transfer record plumbed to it yet, which is stated in the handoff rather than hidden here.
 */
class ReadingWhileDownloadingTest {

    private fun book(
        format: PublicationFormat = PublicationFormat.CBZ,
        isFixedLayout: Boolean = false,
    ) = Publication(
        identity = PublicationIdentity(contentDigest = "fine-print"),
        format = format,
        displayTitle = "Fine Print",
        origin = MetadataOrigin.EMBEDDED,
        streaming = StreamingCapability.STREAMS,
        isFixedLayout = isFixedLayout,
    )

    private val fromACatalogue = Provenance(
        place = Provenance.Place.LIBRARY,
        libraryName = "Books",
        readiness = Provenance.Readiness.READY,
        isAlsoElsewhere = false,
    )

    private fun transfer(state: Download.State) = Download(
        id = "urn:storyarc:6",
        title = "Fine Print",
        remote = "https://books.example/fine-print.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = state,
    )

    /** The page's own two lines, with the platform answers a comic gets. */
    private fun actionFor(
        publication: Publication,
        local: String?,
        transfer: Download?,
    ): PrimaryAction {
        val where = ReadingAddress.of(
            local = local,
            transfer = transfer,
            readsWhereItLies = readsFromAnAddress(publication),
        )
        return primaryActionOf(
            publication = publication,
            provenance = fromACatalogue,
            isOnDevice = local != null,
            hasProgress = false,
            readsWhereItLies = local != null || (where != null && ReadingAddress.isStreamed(where)),
        )
    }

    @Test
    fun `a publication that is still downloading opens rather than offering a download`() {
        val action = actionFor(book(), local = null, transfer = transfer(Download.State.Running))

        assertEquals(PrimaryAction.READ, action)
        assertTrue(action.opensTheBook)
    }

    @Test
    fun `with no transfer at all the page still asks for a copy`() {
        val action = actionFor(book(), local = null, transfer = null)

        assertEquals(PrimaryAction.NEEDS_DOWNLOAD, action)
        assertFalse(action.opensTheBook)
    }

    @Test
    fun `a failed transfer asks for a copy, because a retry is what the reader needs`() {
        val action = actionFor(
            book(),
            local = null,
            transfer = transfer(Download.State.Failed("the server refused", 3)),
        )

        assertEquals(PrimaryAction.NEEDS_DOWNLOAD, action)
    }

    @Test
    fun `an audiobook still downloading asks for a copy, because the player wants a file`() {
        val action = actionFor(
            book(format = PublicationFormat.M4B),
            local = null,
            transfer = transfer(Download.State.Running),
        )

        assertEquals(PrimaryAction.NEEDS_DOWNLOAD, action)
    }

    @Test
    fun `a PDF still downloading asks for a copy, because it is drawn from a file`() {
        val action = actionFor(
            book(format = PublicationFormat.PDF),
            local = null,
            transfer = transfer(Download.State.Running),
        )

        assertEquals(PrimaryAction.NEEDS_DOWNLOAD, action)
    }

    @Test
    fun `a reflowable EPUB still downloading asks for a copy, because Readium is given a file`() {
        val action = actionFor(
            book(format = PublicationFormat.EPUB),
            local = null,
            transfer = transfer(Download.State.Running),
        )

        assertEquals(PrimaryAction.NEEDS_DOWNLOAD, action)
    }

    @Test
    fun `a fixed-layout EPUB still downloading opens, because it is read as a comic`() {
        val action = actionFor(
            book(format = PublicationFormat.EPUB, isFixedLayout = true),
            local = null,
            transfer = transfer(Download.State.Running),
        )

        assertEquals(PrimaryAction.READ, action)
    }
}
