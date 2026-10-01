package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaReadingListItem
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
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
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `collections-and-reading-lists` task 7.14: an end screen offers only an entry that taking
 * it can open. The library's next can be a Kavita or OPDS row with no file on this device,
 * and [offeredNext] leaves that row out. A server list the reader is inside still answers
 * first (task 7.3): its entry has no file yet, and taking it fetches one.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class OfferedNextTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    private val corpus: File = File(
        requireNotNull(System.getProperty("storyarc.library.projectDir")) {
            "storyarc.library.projectDir is not set — see this module's build.gradle.kts"
        },
    ).resolve("../../../..").canonicalFile.resolve("packages/test-fixtures")

    private val managed: File
        get() = application.getExternalFilesDir(null) ?: application.filesDir

    private val server = UUID.randomUUID()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        managed.deleteRecursively()
        managed.mkdirs()
        application.cacheDir.resolve("library.json").delete()
    }

    @After
    fun tearDown() {
        ServerListContext.clear()
        Dispatchers.resetMain()
    }

    private fun remote(chapter: Int) = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(server, "chapter:$chapter"),
        ),
        format = PublicationFormat.CBZ,
        displayTitle = "Issue #$chapter",
        origin = MetadataOrigin.AUTHORITATIVE,
    )

    private suspend fun libraryWith(vararg fixtures: String): Pair<LibraryViewModel, List<Publication>> {
        fixtures.forEachIndexed { index, fixture ->
            corpus.resolve("comics/$fixture").copyTo(managed.resolve("0$index.cbz"), overwrite = true)
        }
        val model = LibraryViewModel(application)
        model.rescan()
        model.scanJob?.join()
        return model to model.publications.value.sortedBy { model.location(it) }
    }

    @Test
    fun `a list's next row with no file on this device is not offered`() = runTest {
        val (model, local) = libraryWith("single-page.cbz")
        val away = remote(41)
        model.adopt(away, sourceId = null)
        model.createList("Crossover")
        model.appendToList(listOf(local[0].id, away.id), model.shelves.value.lists.single().id)

        assertEquals("The library's own next is the row with no file.", away.id, model.next(local[0])?.id)
        assertNull("A row with no file was offered, and taking it would open nothing.", model.offeredNext(local[0]))
    }

    @Test
    fun `a list's next row with a file is offered`() = runTest {
        val (model, local) = libraryWith("single-page.cbz", "natural-sort.cbz")
        model.createList("Crossover")
        model.appendToList(listOf(local[0].id, local[1].id), model.shelves.value.lists.single().id)

        assertEquals(local[1].id, model.offeredNext(local[0])?.id)
        assertEquals(local[0].id, model.offeredPrevious(local[1])?.id)
    }

    @Test
    fun `the server list the reader is inside answers before the library`() = runTest {
        val (model, local) = libraryWith("single-page.cbz")
        val reading = remote(10)
        model.adopt(reading, sourceId = null)
        model.createList("Crossover")
        model.appendToList(listOf(reading.id, local[0].id), model.shelves.value.lists.single().id)
        ServerListContext.opened(
            ServerListContext.Place(
                serverId = server.toString(),
                serverAddress = KavitaAddress("http://localhost:1", "key"),
                listId = 8,
                entries = listOf(
                    KavitaReadingListItem(chapterId = 10, order = 0, title = "Issue #10"),
                    KavitaReadingListItem(chapterId = 11, order = 1, title = "Issue #11"),
                ),
                position = 0,
            ),
        )

        assertEquals("chapter:11", model.offeredNext(reading)?.identity?.serverIdentifier?.remoteId)
    }
}
