package app.storyarc.core.persistence

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadState
import app.storyarc.core.model.RecentSearches
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/**
 * `library-browsing` requires filters and the layout to survive leaving the
 * library. Instrumented because `SharedPreferences` needs a real `Context`, and
 * what is being asserted is that the values actually round-trip through storage.
 *
 * iOS's `LibraryPreferencesTests` asserts the same four things.
 */
@RunWith(AndroidJUnit4::class)
class LibraryPreferencesTest {

    private fun fresh(): LibraryPreferences {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        // A private file per test, so one test's leftovers cannot pass another.
        val name = "test-${UUID.randomUUID()}"
        return LibraryPreferences(context.getSharedPreferences(name, Context.MODE_PRIVATE))
    }

    @Test
    fun filters_and_sorting_come_back_on_the_next_launch() {
        val preferences = fresh()
        preferences.save(
            LibraryQuery(
                readStates = setOf(ReadState.IN_PROGRESS),
                formats = setOf(PublicationFormat.CBZ, PublicationFormat.PDF),
                sort = LibrarySort.LAST_READ,
                ascending = false,
            ),
        )

        val restored = preferences.query()
        assertEquals(setOf(ReadState.IN_PROGRESS), restored.readStates)
        assertEquals(setOf(PublicationFormat.CBZ, PublicationFormat.PDF), restored.formats)
        assertEquals(LibrarySort.LAST_READ, restored.sort)
        assertEquals(false, restored.ascending)
    }

    @Test
    fun a_search_term_is_not_remembered() {
        val preferences = fresh()
        // A filter outlives a session. A half-typed search does not, and reopening
        // the app to a library narrowed by yesterday's word reads as a bug.
        preferences.save(LibraryQuery(search = "sandman", sort = LibrarySort.SERIES))

        assertTrue(preferences.query().search.isEmpty())
        assertEquals(LibrarySort.SERIES, preferences.query().sort)
    }

    @Test
    fun recent_searches_survive_the_launch_the_term_they_came_from_does_not() {
        val preferences = fresh()
        assertTrue(preferences.recentSearches().isEmpty)
        preferences.save(RecentSearches().recording("sandman").recording("bone"))
        assertEquals(listOf("bone", "sandman"), preferences.recentSearches().terms)
    }

    @Test
    fun the_layout_defaults_to_the_grid_and_survives_a_change() {
        val preferences = fresh()
        assertEquals(LibraryLayout.GRID, preferences.layout())
        preferences.save(LibraryLayout.LIST)
        assertEquals(LibraryLayout.LIST, preferences.layout())
    }
}
