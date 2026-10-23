package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Task 28.6: a finished title does not offer *Continue*. `readFraction` answers 1 for a finished
 * record so the shelf draws a full bar, which is why the title page asks this instead; iOS's
 * `continuesInPlace` is the same rule. Task 20.1: the positions say when they were first read,
 * and a read after a save sees the saved position.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ContinuesInPlaceTest {

    private val identity = PublicationIdentity(normalizedPath = "/Comics/Bone 01.cbz")
    private val book = Publication(
        identity = identity,
        format = PublicationFormat.CBZ,
        displayTitle = "Bone 01",
        origin = MetadataOrigin.INFERRED,
    )

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun library(store: ProgressStore) =
        LibraryViewModel(ApplicationProvider.getApplicationContext<Application>(), progressStore = store)
            .also { it._publications.value = listOf(book) }

    @Test
    fun `a started title continues, a finished one and an unopened one do not`() = runTest {
        val store = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        val library = library(store)
        library.refreshProgress()?.join()
        assertFalse(library.continuesInPlace(book))

        store.save(ReadingProgress(identity, ReadingPosition.Page(3, 10), updatedAtEpochMillis = 1))
        library.refreshProgress()?.join()
        assertTrue(library.continuesInPlace(book))
        assertEquals(ReadingPosition.Page(3, 10).fraction.toFloat(), library.readFraction(book))

        store.mark(identity, isFinished = true)
        library.refreshProgress()?.join()
        assertFalse(library.continuesInPlace(book))
        assertEquals(1f, library.readFraction(book))
    }

    @Test
    fun `the positions are loaded after the first read, and a later read sees a later save`() = runTest {
        val store = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        val library = library(store)
        assertFalse(library.progressLoaded.value)

        library.refreshProgress()?.join()
        assertTrue(library.progressLoaded.value)
        assertTrue(library.continueReading.value.isEmpty())

        store.save(ReadingProgress(identity, ReadingPosition.Page(3, 10), updatedAtEpochMillis = 1))
        library.refreshProgress()?.join()
        assertEquals(listOf(book), library.continueReading.value)
    }
}
