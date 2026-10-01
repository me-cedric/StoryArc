package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `collections-and-reading-lists` task 7.10: `Shelves.renamingCollection` and
 * `Shelves.renamingList` have had a model to answer since the day they were written; these
 * are the view-model calls `ShelfRenameDialog` makes, and `ShelvesTest` already covers the
 * model rule itself (a blank name is refused) that these two simply carry through.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShelfRenamingTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `renaming a collection changes its name and saves it`() {
        val viewModel = LibraryViewModel(application)
        viewModel.createCollection("Image Comics")
        val id = viewModel.shelves.value.collections.first().id

        viewModel.renameCollection(id, "Marvel")

        assertEquals("Marvel", viewModel.shelves.value.collections.first().name)
    }

    @Test
    fun `renaming a reading list changes its name and saves it`() {
        val viewModel = LibraryViewModel(application)
        viewModel.createList("Crossover")
        val id = viewModel.shelves.value.lists.first().id

        viewModel.renameList(id, "Infinity War tie-ins")

        assertEquals("Infinity War tie-ins", viewModel.shelves.value.lists.first().name)
    }

    @Test
    fun `renaming to a blank name does nothing`() {
        val viewModel = LibraryViewModel(application)
        viewModel.createCollection("Image Comics")
        val id = viewModel.shelves.value.collections.first().id

        viewModel.renameCollection(id, "   ")

        assertEquals("Image Comics", viewModel.shelves.value.collections.first().name)
    }
}
