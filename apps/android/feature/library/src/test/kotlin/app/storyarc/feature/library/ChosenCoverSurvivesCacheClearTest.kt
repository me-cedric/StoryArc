package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.format.CoverOverrideStore
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.StorageUsage
import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 2.5: "a chosen cover survives a cache clear".
 *
 * `cover-art` puts it in the reader's own words: "every chosen cover is still there, because a
 * chosen cover is data the reader created and not a cache". Composed against a real `Context`
 * rather than against two temporary directories, because the promise is about *where* the
 * store puts things — a test that handed the store its own directory would pass whatever the
 * app did. iOS's `ChosenCoverSurvivesCacheClearTests.swift` is its twin.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ChosenCoverSurvivesCacheClearTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    private val publication = Publication(
        identity = PublicationIdentity(contentDigest = "digest-for-the-chosen-cover"),
        format = PublicationFormat.M4B,
        displayTitle = "Ripped From A CD",
        origin = MetadataOrigin.INFERRED,
    )

    @Test
    fun `clearing the cache empties the cover cache and leaves the chosen covers`() {
        val picture = byteArrayOf(0x42, 0x43)
        val cached = File(application.cacheDir, "covers").apply { mkdirs() }
            .resolve("ab12-200.jpg")
            .apply { writeBytes(byteArrayOf(1)) }
        val overrides = CoverOverrideStore(appDirectory())
        val chosen = overrides.store(picture, publication)

        StorageUsage(application).clearCache()

        assertFalse("the decoded cover is a cache and goes", cached.isFile)
        assertTrue("the chosen cover is not", chosen!!.isFile)
        assertArrayEquals(picture, overrides.bytes(publication))
    }

    @Test
    fun `chosen covers are not kept anywhere the cache clear reaches`() {
        // The folder the app itself uses, read from the view model. A test that named its own
        // folder would stay green if the app moved its covers under the cache.
        val directory = appDirectory().canonicalPath

        listOfNotNull(application.cacheDir, application.externalCacheDir).forEach { cache ->
            assertFalse(
                "chosen covers must not live under $cache",
                directory.startsWith(cache.canonicalPath + File.separator),
            )
        }
        assertEquals(
            File(application.filesDir, "cover-overrides").canonicalPath,
            directory,
        )
    }

    /** Where the app keeps chosen covers: the view model's own answer, not one built here. */
    private fun appDirectory(): File = LibraryViewModel(application).coverOverrideDirectory
}
