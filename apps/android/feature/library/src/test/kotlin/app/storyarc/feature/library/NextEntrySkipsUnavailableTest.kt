package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * `collections-and-reading-lists` task 7.1: a reading list's next/previous flow must walk
 * forward (or back) past entries whose publication is gone, and only then try the next list
 * or fall back to the series. [LibraryViewModel.next] and [LibraryViewModel.previous] used to
 * give up on the first unavailable id and jump straight to the series fallback.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class NextEntrySkipsUnavailableTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    private val corpus: File = File(
        requireNotNull(System.getProperty(MODULE_DIRECTORY)) {
            "$MODULE_DIRECTORY is not set — see this module's build.gradle.kts"
        },
    ).resolve("../../../..").canonicalFile.resolve("packages/test-fixtures")

    private val managed: File
        get() = application.getExternalFilesDir(null) ?: application.filesDir

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        managed.deleteRecursively()
        managed.mkdirs()
        application.cacheDir.resolve("library.json").delete()
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun copy(fixture: String, name: String): File {
        val file = managed.resolve(name)
        corpus.resolve("comics/$fixture").copyTo(file, overwrite = true)
        return file
    }

    @Test
    fun `next walks past a gone entry to the next available one in the same list`() = runTest {
        copy("single-page.cbz", "01.cbz")
        copy("natural-sort.cbz", "02.cbz")
        copy("double-page-spread.cbz", "03.cbz")

        val model = LibraryViewModel(application)
        model.rescan()
        model.scanJob?.join()

        // Order by location to make A/B/C deterministic.
        val sorted = model.publications.value.sortedBy { model.location(it) }
        val (first, second, third) = Triple(sorted[0], sorted[1], sorted[2])

        model.createList("Crossover")
        val listId = model.shelves.value.lists.single().id
        model.appendToList(listOf(first.id, "gone-1", second.id, "gone-2", third.id), listId)

        assertEquals(
            "next() gave up at the first gone id instead of walking past it.",
            second.id,
            model.next(first)?.id,
        )
        assertEquals(
            "next() gave up at the second gone id instead of walking past it.",
            third.id,
            model.next(second)?.id,
        )
    }

    @Test
    fun `previous walks back past a gone entry to the prior available one`() = runTest {
        copy("single-page.cbz", "01.cbz")
        copy("natural-sort.cbz", "02.cbz")
        copy("double-page-spread.cbz", "03.cbz")

        val model = LibraryViewModel(application)
        model.rescan()
        model.scanJob?.join()

        val sorted = model.publications.value.sortedBy { model.location(it) }
        val (first, second, third) = Triple(sorted[0], sorted[1], sorted[2])

        model.createList("Crossover")
        val listId = model.shelves.value.lists.single().id
        model.appendToList(listOf(first.id, "gone-1", second.id, "gone-2", third.id), listId)

        assertEquals(
            "previous() gave up at a gone id instead of walking back past it.",
            second.id,
            model.previous(third)?.id,
        )
        assertEquals(
            "previous() gave up at a gone id instead of walking back past it.",
            first.id,
            model.previous(second)?.id,
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
    }
}
