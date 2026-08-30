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

/**
 * The one action the page offers, and the two states in which it cannot be honoured.
 *
 * The wording of this control is an accessibility requirement, not a layout preference:
 * `publication-detail` puts it first in the reading order after the title and requires its
 * label to say "which of those will happen before it is taken". A screen-reader user learns
 * the outcome before taking it, which is only true if the outcome is decided here rather
 * than guessed at the button.
 */
class DetailActionsTest {

    private fun book(
        streaming: StreamingCapability = StreamingCapability.STREAMS,
    ) = Publication(
        identity = PublicationIdentity(contentDigest = "bone"),
        format = PublicationFormat.CBZ,
        displayTitle = "Bone",
        origin = MetadataOrigin.EMBEDDED,
        streaming = streaming,
    )

    private fun provenance(readiness: Provenance.Readiness) = Provenance(
        place = Provenance.Place.LIBRARY,
        libraryName = "Home NAS",
        readiness = readiness,
        isAlsoElsewhere = false,
    )

    private val here = Provenance(
        place = Provenance.Place.DEVICE,
        libraryName = null,
        readiness = Provenance.Readiness.READY,
        isAlsoElsewhere = false,
    )

    @Test
    fun anUnreadBookOnTheDeviceSaysRead() {
        val action = primaryActionOf(book(), here, isOnDevice = true, hasProgress = false)

        assertEquals(PrimaryAction.READ, action)
        assertTrue(action.opensTheBook)
    }

    @Test
    fun aStartedBookSaysContinue() {
        val action = primaryActionOf(book(), here, isOnDevice = true, hasProgress = true)

        assertEquals(PrimaryAction.CONTINUE, action)
    }

    @Test
    fun aBookThatIsNeitherHereNorReachableAsksForWhatItNeeds() {
        // The delta: the action "states what it needs in plain language rather than failing
        // when taken", and the download is offered in its place.
        val action = primaryActionOf(
            book(),
            provenance(Provenance.Readiness.SOURCE_AWAY),
            isOnDevice = false,
            hasProgress = false,
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
        )

        assertEquals(PrimaryAction.NEEDS_DOWNLOAD, action)
    }

    @Test
    fun aStreamableBookOpensWithoutBeingDownloadedFirst() {
        val action = primaryActionOf(
            book(),
            provenance(Provenance.Readiness.NOT_DOWNLOADED),
            isOnDevice = false,
            hasProgress = false,
        )

        assertEquals(PrimaryAction.READ, action)
    }

    @Test
    fun aRefusedContainerIsNeverOfferedAsContinue() {
        // A position can be recorded against a publication whose container later turns out
        // to be unreadable. Offering *Continue* there is a button that fails when pressed,
        // which is the failure this ordering exists to prevent.
        val action = primaryActionOf(
            book(StreamingCapability.REFUSED),
            here,
            isOnDevice = true,
            hasProgress = true,
        )

        assertEquals(PrimaryAction.REFUSED, action)
        assertFalse(action.opensTheBook)
    }

    @Test
    fun onlyTheTwoOpeningStatesGoWithoutAnExplanation() {
        // "An action that does not apply is absent, not shown disabled without explanation."
        for (action in PrimaryAction.entries) {
            assertEquals(action.name, action.opensTheBook, action.explanation() == null)
        }
    }
}
