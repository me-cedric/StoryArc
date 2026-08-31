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

    @Test
    fun onlyTheRefusedStateGoesWithoutALabel() {
        // A refused publication has nothing to offer under any circumstances, so it draws
        // no button — and a button label with no button is a string four locales carry and
        // nothing can render. Every other state has one, because every other state has a
        // button somewhere in its range of inputs.
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
        // The defect this replaces: a `NEEDS_DOWNLOAD` publication drew *Download it* as
        // the primary action and carried a second *Download it* in the overflow beside it,
        // because the two were gated on the same non-null callback in different
        // composables. One value for one decision makes both-at-once unrepresentable.
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
        // The two the reader did not cause. The page wants one thing of them and it is the
        // fetch, so it is the primary rather than an entry in a menu.
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
        // Already on the device, or a source with no route to a copy. `AppScreens` passes a
        // null `onDownload` for both, and neither control may invent one.
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
        // iOS excludes it through `canCopy`, and for the same reason: fetching a container
        // no decoder will open produces a local copy that still cannot be read.
        assertEquals(
            DownloadControl.NONE,
            downloadControl(PrimaryAction.REFUSED, canDownload = true),
        )
    }
}
