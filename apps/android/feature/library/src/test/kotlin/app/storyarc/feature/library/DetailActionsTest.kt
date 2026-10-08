package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.StreamingCapability
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DetailActionsTest {

    private fun book(
        streaming: StreamingCapability = StreamingCapability.STREAMS,
        format: PublicationFormat = PublicationFormat.CBZ,
    ) = Publication(
        identity = PublicationIdentity(contentDigest = "bone"),
        format = format,
        displayTitle = "Bone",
        origin = MetadataOrigin.EMBEDDED,
        streaming = streaming,
    )

    private fun provenance(readiness: Provenance.Readiness) = Provenance(
        place = Provenance.Place.LIBRARY,
        libraryName = "Home NAS",
        readiness = readiness,
        alsoIn = null,
    )

    private val here = Provenance(
        place = Provenance.Place.DEVICE,
        libraryName = null,
        readiness = Provenance.Readiness.READY,
        alsoIn = null,
    )

    @Test
    fun anUnreadBookOnTheDeviceSaysRead() {
        val action = primaryActionOf(
            book(), here, isOnDevice = true, hasProgress = false, readsWhereItLies = true,
        )

        assertEquals(PrimaryAction.READ, action)
        assertTrue(action.opensTheBook)
    }

    @Test
    fun aStartedBookSaysContinue() {
        val action = primaryActionOf(
            book(), here, isOnDevice = true, hasProgress = true, readsWhereItLies = true,
        )

        assertEquals(PrimaryAction.CONTINUE, action)
    }

    @Test
    fun anAudiobookNobodyHasStartedSaysListen() {
        val action = primaryActionOf(
            book(format = PublicationFormat.M4B),
            here,
            isOnDevice = true,
            hasProgress = false,
            readsWhereItLies = true,
        )

        assertEquals(PrimaryAction.LISTEN, action)
        assertTrue(action.opensTheBook)
    }

    @Test
    fun aStartedAudiobookSaysContinueListening() {
        val action = primaryActionOf(
            book(format = PublicationFormat.M4B),
            here,
            isOnDevice = true,
            hasProgress = true,
            readsWhereItLies = true,
        )

        assertEquals(PrimaryAction.CONTINUE_LISTENING, action)
    }

    @Test
    fun everyAudioContainerIsListenedTo() {
        for (format in PublicationFormat.entries.filter { it.isAudio }) {
            assertEquals(
                format.name,
                PrimaryAction.LISTEN,
                primaryActionOf(
                    book(format = format),
                    here,
                    isOnDevice = true,
                    hasProgress = false,
                    readsWhereItLies = true,
                ),
            )
        }
    }

    @Test
    fun readingAndListeningNeverBorrowEachOthersWords() {
        val words = listOf(
            PrimaryAction.READ,
            PrimaryAction.CONTINUE,
            PrimaryAction.LISTEN,
            PrimaryAction.CONTINUE_LISTENING,
        ).map { it.label() }

        assertEquals("four openings, four labels", words.size, words.toSet().size)
    }

    @Test
    fun aBookThatIsNeitherHereNorReachableAsksForWhatItNeeds() {
        val action = primaryActionOf(
            book(),
            provenance(Provenance.Readiness.SOURCE_AWAY),
            isOnDevice = false,
            hasProgress = false,
            readsWhereItLies = false,
        )

        assertEquals(PrimaryAction.NEEDS_SOURCE, action)
        assertFalse(action.opensTheBook)
    }

    @Test
    fun aDownloadOnlyFormatHasToArriveFirst() {
        val action = primaryActionOf(
            book(StreamingCapability.DOWNLOAD_ONLY),
            provenance(Provenance.Readiness.NOT_DOWNLOADED),
            isOnDevice = false,
            hasProgress = false,
            readsWhereItLies = true,
        )

        assertEquals(PrimaryAction.NEEDS_DOWNLOAD, action)
    }

    /**
     * This case used to assert `READ`, and that assertion was the defect.
     *
     * A catalogue row has a server identifier and no path, so nothing on the device can open
     * it and nothing in the app can reach it where it lies. The page drew *Read* for it and
     * the tap did nothing at all: no navigation, no message, no failure. `publication-detail`
     * forbids exactly that -- "the primary action is never one that fails when it is taken" --
     * so the answer for a publication with no way in is the copy, whatever the container said
     * about streaming.
     */
    @Test
    fun aBookNothingCanOpenWhereItLiesAsksForACopy() {
        val action = primaryActionOf(
            book(),
            provenance(Provenance.Readiness.NOT_DOWNLOADED),
            isOnDevice = false,
            hasProgress = false,
            readsWhereItLies = false,
        )

        assertEquals(PrimaryAction.NEEDS_DOWNLOAD, action)
        assertFalse(action.opensTheBook)
    }

    @Test
    fun aBookTheAppReadsWhereItLiesOpensWithoutACopyFirst() {
        val action = primaryActionOf(
            book(),
            provenance(Provenance.Readiness.NOT_DOWNLOADED),
            isOnDevice = false,
            hasProgress = false,
            readsWhereItLies = true,
        )

        assertEquals(PrimaryAction.READ, action)
        assertTrue(action.opensTheBook)
    }

    @Test
    fun aBookReadWhereItLiesIsStillOfferedAsACopyBeside() {
        val action = primaryActionOf(
            book(),
            provenance(Provenance.Readiness.NOT_DOWNLOADED),
            isOnDevice = false,
            hasProgress = false,
            readsWhereItLies = true,
        )

        assertEquals(DownloadControl.OVERFLOW, downloadControl(action, canDownload = true))
    }

    @Test
    fun aRefusedContainerIsNeverOfferedAsContinue() {
        val action = primaryActionOf(
            book(StreamingCapability.REFUSED),
            here,
            isOnDevice = true,
            hasProgress = true,
            readsWhereItLies = true,
        )

        assertEquals(PrimaryAction.REFUSED, action)
        assertFalse(action.opensTheBook)
    }

    @Test
    fun onlyTheTwoOpeningStatesGoWithoutAnExplanation() {
        for (action in PrimaryAction.entries) {
            assertEquals(action.name, action.opensTheBook, action.explanation() == null)
        }
    }

    @Test
    fun onlyTheRefusedStateGoesWithoutALabel() {
        for (action in PrimaryAction.entries) {
            assertEquals(
                action.name,
                action == PrimaryAction.REFUSED,
                action.label() == null,
            )
        }
    }

    @Test
    fun theDownloadIsOfferedByExactlyOneControl() {
        for (action in PrimaryAction.entries) {
            val control = downloadControl(action, canDownload = true)
            assertEquals(
                action.name,
                action == PrimaryAction.REFUSED,
                control == DownloadControl.NONE,
            )
            assertEquals(action.name, action.opensTheBook, control == DownloadControl.OVERFLOW)
        }
    }

    @Test
    fun theStatesThatCannotOpenYetCarryTheDownloadThemselves() {
        assertEquals(
            DownloadControl.PRIMARY,
            downloadControl(PrimaryAction.NEEDS_DOWNLOAD, canDownload = true),
        )
        assertEquals(
            DownloadControl.PRIMARY,
            downloadControl(PrimaryAction.NEEDS_SOURCE, canDownload = true),
        )
    }

    @Test
    fun nothingOffersADownloadTheAppCannotMake() {
        for (action in PrimaryAction.entries) {
            assertEquals(
                action.name,
                DownloadControl.NONE,
                downloadControl(action, canDownload = false),
            )
        }
    }

    @Test
    fun aRefusedContainerIsNeverOfferedAsADownloadEither() {
        assertEquals(
            DownloadControl.NONE,
            downloadControl(PrimaryAction.REFUSED, canDownload = true),
        )
    }

    // The download offer's size.

    @Test
    fun `the needs-download explanation states the size when the source stated one`() {
        val (resource, size) = explanationResource(PrimaryAction.NEEDS_DOWNLOAD, 400_000_000L, PublicationFormat.CBZ)!!
        assertEquals(R.string.detail_unavailable_sized, resource)
        assertEquals(400_000_000L, size)
    }

    @Test
    fun `an absent or zero size falls back to the sizeless sentence`() {
        // `offline-downloads` requires an unknown size to be stated as an absence rather
        // than as a zero, and a zero directory-entry length is the only shape "nothing
        // stated" can arrive in here.
        for (fileSize in listOf(null, 0L)) {
            val (resource, size) = explanationResource(PrimaryAction.NEEDS_DOWNLOAD, fileSize, PublicationFormat.CBZ)!!
            assertEquals("fileSize=$fileSize", R.string.detail_unavailable, resource)
            assertEquals("fileSize=$fileSize", null, size)
        }
    }

    @Test
    fun `a size is never stated for an explanation that is not the download one`() {
        val (resource, size) = explanationResource(PrimaryAction.NEEDS_SOURCE, 400_000_000L, PublicationFormat.CBZ)!!
        assertEquals(R.string.detail_needs_source, resource)
        assertEquals(null, size)
    }

    // Why a refused publication does not open.

    @Test
    fun `a cb7 is refused by its container, never as solid compression`() {
        // `SmbContributor` refuses a CB7 share row from its name alone. The cell, the list row
        // and the publication page used to say every refused row uses solid compression,
        // which is true of a solid RAR4 and false of a CB7.
        assertEquals(R.string.library_cannot_open_cb7, refusalSentence(PublicationFormat.CB7))
        assertEquals(
            R.string.library_cannot_open_cb7 to null,
            explanationResource(PrimaryAction.REFUSED, 400_000_000L, PublicationFormat.CB7),
        )
    }

    @Test
    fun `a solid rar4 is refused by its compression`() {
        assertEquals(R.string.library_cell_cannot_open, refusalSentence(PublicationFormat.CBR))
        assertEquals(
            R.string.library_cell_cannot_open to null,
            explanationResource(PrimaryAction.REFUSED, null, PublicationFormat.CBR),
        )
    }
}
