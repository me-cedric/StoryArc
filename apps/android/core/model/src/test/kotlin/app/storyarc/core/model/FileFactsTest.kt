package app.storyarc.core.model

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * When a publication may be trusted rather than re-read.
 *
 * `local-library` asks a returning app to reconcile "by comparing file modification times
 * and sizes rather than re-reading every archive". The risk in that sentence is not the
 * comparison — it is the *unknowns*, where trusting one costs a library that disagrees with
 * the disk and never finds out.
 *
 * iOS's `FileFactsTests` asserts the same table.
 */
class FileFactsTest {

    private val moment = 1_700_000_000_000L

    private fun publication(size: Long? = 1024, modified: Long? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/bone.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = "Bone",
        origin = MetadataOrigin.EMBEDDED,
        fileSize = size,
        modifiedAtEpochMillis = modified,
    )

    @Test
    fun `same size and same moment is unchanged`() {
        assertTrue(publication(modified = moment).matchesFile(1024, moment))
    }

    @Test
    fun `a different size is a different file`() {
        assertFalse(publication(modified = moment).matchesFile(2048, moment))
    }

    @Test
    fun `a file written since is re-read even at the same size`() {
        // The case that makes size alone insufficient: an editor that rewrites a container
        // in place can leave its length exactly as it was.
        assertFalse(publication(modified = moment).matchesFile(1024, moment + 60_000))
    }

    @Test
    fun `anything unknown is re-read rather than trusted`() {
        // A publication indexed before these facts were recorded.
        assertFalse(publication(size = null, modified = moment).matchesFile(1024, moment))
        assertFalse(publication(modified = null).matchesFile(1024, moment))
        // A file the walk could not stat.
        assertFalse(publication(modified = moment).matchesFile(null, moment))
        assertFalse(publication(modified = moment).matchesFile(1024, null))
    }
}
