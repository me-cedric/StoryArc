package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CoverFetch
import app.storyarc.core.catalogue.CoverFetched
import app.storyarc.core.catalogue.CoverTransport
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.SettingsStore
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The lookup is a rung of the ladder `LibraryViewModel.cover` climbs, not a client nobody calls.
 *
 * Task 6.1 and task 3.2 of `cover-for-every-publication`. The view model is the production
 * path: it reads the file on the device, finds the ISBN in its package document, and asks the
 * client only while the stored setting is on. The transport is the one thing replaced, so the
 * test counts what would leave the device. iOS's `CoverLookupLadderTests` is its twin.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CoverLookupLadderWiringTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val application: Application get() = ApplicationProvider.getApplicationContext()
    private val asked = mutableListOf<CoverFetch>()

    @Before
    fun countRequests() {
        CoverLookup.transport = CoverTransport { request ->
            asked += request
            CoverFetched(404, ByteArray(0), request.url)
        }
        CoverLookup.reset()
    }

    @After
    fun restore() {
        CoverLookup.transport = app.storyarc.core.catalogue.PlatformCoverTransport
        CoverLookup.reset()
    }

    private fun setting(on: Boolean) =
        SettingsStore.open(application).save(AppSettings.Defaults.copy(lookUpMissingCovers = on))

    private fun epub(isbn: String?): File {
        val identifiers = listOfNotNull("urn:uuid:5b4c1f9e-0c1d-4b5e-8f7a-1234567890ab", isbn)
        val opf = """<package version="3.0"><metadata><dc:title>Fine Print</dc:title>
            ${identifiers.joinToString("") { "<dc:identifier>$it</dc:identifier>" }}
            </metadata><manifest></manifest><spine></spine></package>"""
        val file = folder.newFile("book-${asked.size}-${System.nanoTime()}.epub")
        ZipOutputStream(file.outputStream()).use { zip ->
            mapOf(
                "mimetype" to "application/epub+zip",
                "META-INF/container.xml" to
                    """<container><rootfiles><rootfile full-path="package.opf"/></rootfiles></container>""",
                "package.opf" to opf,
            ).forEach { (name, text) ->
                zip.putNextEntry(ZipEntry(name))
                zip.write(text.toByteArray())
                zip.closeEntry()
            }
        }
        return file
    }

    private fun coverOf(file: File): Any? = runBlocking {
        val library = LibraryViewModel(application)
        val publication = Publication(
            identity = PublicationIdentity(contentDigest = file.name, normalizedPath = file.path),
            format = PublicationFormat.EPUB,
            displayTitle = "Fine Print",
            origin = MetadataOrigin.INFERRED,
        )
        library.locations[publication.id] = file.path
        library.cover(publication, 200)
    }

    @Test
    fun `a book with no cover of its own and an ISBN asks Open Library once, with the switch on`() {
        setting(on = true)

        coverOf(epub("urn:isbn:9780141187761"))

        assertEquals(
            listOf("https://covers.openlibrary.org/b/isbn/9780141187761-L.jpg?default=false"),
            asked.map { it.url },
        )
    }

    @Test
    fun `the same book asks nothing while the switch is off`() {
        setting(on = false)

        coverOf(epub("urn:isbn:9780141187761"))

        assertTrue("asked ${asked.map { it.url }}", asked.isEmpty())
    }

    @Test
    fun `a book with no ISBN asks nothing even with the switch on`() {
        setting(on = true)

        coverOf(epub(isbn = null))

        assertTrue(asked.isEmpty())
    }
}
