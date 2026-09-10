package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.LibraryCache
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * That a server's shelf survives the server going away.
 *
 * `sources`: the catalogue is cached "so the library opens instantly and stays browsable
 * while offline". A local file's row survives a restart because the file does. A server's
 * row has nothing on disk behind it, so the only thing that can carry it across a launch is
 * the snapshot — and a reader on a train with no signal is exactly the case the caching
 * exists for.
 *
 * **The half that was missing.** `readServers` adopted a server's publications and rebuilt
 * the shelf, and never wrote the snapshot. A reader whose library is one Kavita server and
 * no folders had nothing cached at all: the shelf was written only when a *folder* walk
 * finished, and they had no folder to walk. Opening the app offline showed an empty
 * library, which is the state the cache exists to prevent.
 *
 * iOS's `CachedServerRowsTests` asserts the same three claims.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CachedServerRowsTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    private val source = UUID.randomUUID()

    private val cache: LibraryCache
        get() = LibraryCache(File(application.cacheDir, "library.json"))

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        cache.clear()
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        cache.clear()
    }

    private fun row(remoteId: String, title: String) = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(
                sourceId = source,
                remoteId = remoteId,
            ),
        ),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.AUTHORITATIVE,
        sourceId = source,
    )

    private fun server() = Source(
        id = source,
        kind = SourceKind.KAVITA_SERVER,
        displayName = "A server",
        locator = "https://example.invalid",
    )

    private fun cached(vararg rows: Publication) {
        cache.write(
            LibraryCache.Snapshot(
                refreshedAtEpochMillis = 1_757_000_000_000,
                publications = rows.toList(),
            ),
        )
    }

    @Test
    fun `with every source unreachable the cached shelf still draws`() = runTest {
        cached(row("chapter:1", "One"), row("chapter:2", "Two"))
        val model = LibraryViewModel(application)

        model.restoreCachedLibrary()

        assertEquals(
            "A reader offline saw an empty library. The rows are cached for exactly this.",
            listOf("One", "Two"),
            model.publications.value.map { it.displayTitle },
        )
    }

    @Test
    fun `the shelf says when it was last refreshed, so a reader knows it is last session's`() =
        runTest {
            cached(row("chapter:1", "One"))
            val model = LibraryViewModel(application)

            model.restoreCachedLibrary()

            assertEquals(1_757_000_000_000, model.cachedAt.value)
        }

    @Test
    fun `clearing one source's cache takes its rows and leaves the rest`() = runTest {
        val other = UUID.randomUUID()
        val mine = row("chapter:1", "Mine")
        val theirs = mine.copy(
            identity = PublicationIdentity(
                serverIdentifier = PublicationIdentity.ServerIdentifier(other, "chapter:9"),
            ),
            displayTitle = "Theirs",
            sourceId = other,
        )
        cached(mine, theirs)
        val model = LibraryViewModel(application)
        model.restoreCachedLibrary()

        model.clearSourceCache(server())

        assertEquals(
            listOf("Theirs"),
            model.publications.value.map { it.displayTitle },
        )
        assertEquals(
            "The rows went from the shelf and stayed in the snapshot, so the next launch" +
                " puts back exactly what the reader asked to be rid of.",
            listOf("Theirs"),
            cache.read()?.publications?.map { it.displayTitle },
        )
    }

    @Test
    fun `a source with nothing cached is not asked to clear anything`() = runTest {
        cached(row("chapter:1", "One"))
        val model = LibraryViewModel(application)
        model.restoreCachedLibrary()
        val untouched = Source(
            id = UUID.randomUUID(),
            kind = SourceKind.OPDS_CATALOG,
            displayName = "Another",
            locator = "https://elsewhere.invalid",
        )

        model.clearSourceCache(untouched)

        assertEquals(1, model.publications.value.size)
        assertNotNull(cache.read())
    }

    @Test
    fun `nothing a source put on the shelf carries a secret into the cache`() = runTest {
        // The rows a source contributes are identifiers, not addresses — the address and
        // its key live in the source registry and the credential store, and a request is
        // built from those at the moment it is made. This is a tripwire on that: a row that
        // started carrying an acquisition URL would put a reader's API key in a file the
        // Privacy screen describes as "cached content".
        cached(row("chapter:1", "One"), row("opds:urn:uuid:9", "Two"))

        val written = File(application.cacheDir, "library.json").readText()

        for (secret in listOf("apiKey", "api_key", "?key=", "Authorization", "password")) {
            assertFalse(
                "The library cache holds something that looks like a secret: $secret.",
                written.contains(secret, ignoreCase = true),
            )
        }
        assertTrue("The snapshot is not the rows at all.", written.contains("chapter:1"))
    }
}
