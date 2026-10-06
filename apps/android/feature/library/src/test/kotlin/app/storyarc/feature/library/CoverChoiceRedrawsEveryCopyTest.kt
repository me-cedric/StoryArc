package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `cover-for-every-publication` tasks 2.2 to 2.4: a chosen cover is drawn at once, on every
 * copy it belongs to.
 *
 * The store files a chosen cover under the content digest, so two copies of one file share
 * it. Redrawing only the copy the reader acted on left the other showing the old picture for
 * the rest of the launch.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CoverChoiceRedrawsEveryCopyTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `removing a cover redraws every copy of the file and nothing else`() = runTest {
        val model = LibraryViewModel(application)
        val acted = book("a", digest = "same-bytes")
        val copy = book("b", digest = "same-bytes")
        val other = book("c", digest = "other-bytes")
        model._publications.value = listOf(acted, copy, other)

        model.removeChosenCover(acted)

        assertEquals(1, model.coverRevision(acted))
        assertEquals("The other copy of the same file kept its old cover.", 1, model.coverRevision(copy))
        assertEquals(0, model.coverRevision(other))
    }

    private fun book(path: String, digest: String) = Publication(
        identity = PublicationIdentity(contentDigest = digest, normalizedPath = "/books/$path.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = path,
        origin = MetadataOrigin.INFERRED,
    )
}
