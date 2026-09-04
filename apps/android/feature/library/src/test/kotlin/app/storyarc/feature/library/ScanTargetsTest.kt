package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The defect this exists for, in one sentence: adding a folder source emptied the shelf.
 *
 * Seventeen publications before, one after. `rescan` chose *either* the app's own folder
 * *or* the picked trees, so the first folder a reader added stopped the managed folder from
 * being walked at all — and the reconciliation that follows a walk removes everything the
 * walk did not meet. Removing the source brought all seventeen back, which is what made it
 * look like a display problem rather than the shelf being rewritten.
 *
 * Asserted here rather than through [LibraryViewModel], which is an `AndroidViewModel` a JVM
 * unit test cannot build — the same split [SourceRemoval] makes, for the same reason.
 */
class ScanTargetsTest {

    @Test
    fun withNoPickedFolderTheAppsOwnFolderIsStillWalked() {
        assertEquals(listOf(null), ScanTargets.of(emptyList()))
    }

    @Test
    fun aPickedFolderIsWalkedAsWellAsTheAppsOwnFolder() {
        // The regression. `else` here meant the managed folder was dropped, and with it
        // every publication that had been shared to StoryArc or generated into it.
        assertEquals(
            listOf(null, "content://tree/Audiobooks"),
            ScanTargets.of(listOf("content://tree/Audiobooks")),
        )
    }

    @Test
    fun everyPickedFolderIsWalked() {
        assertEquals(
            listOf(null, "content://tree/Comics", "content://tree/Manga"),
            ScanTargets.of(listOf("content://tree/Comics", "content://tree/Manga")),
        )
    }

    @Test
    fun theSameFolderTwiceIsOneWalk() {
        // A tree cannot reach `addFolder` twice, but it can reach `restoreFolders` from the
        // persisted permissions while already being in `_folders`. Walking it twice would
        // open every archive in it twice for one scan.
        assertEquals(
            listOf(null, "content://tree/Comics"),
            ScanTargets.of(listOf("content://tree/Comics", "content://tree/Comics")),
        )
    }

    @Test
    fun theAppsOwnFolderLeadsSoTheShelfFillsFromWhatIsAlreadyOnTheDevice() {
        // Order is not cosmetic: a walk emits as it goes and the first rows drawn are the
        // ones a reader sees first. Local files need no provider round-trip.
        assertEquals(null, ScanTargets.of(listOf("content://tree/Comics")).first())
    }
}
