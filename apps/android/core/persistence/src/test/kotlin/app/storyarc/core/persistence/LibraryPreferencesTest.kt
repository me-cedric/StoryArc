package app.storyarc.core.persistence

import android.content.SharedPreferences
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadState
import app.storyarc.core.model.YearRange
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-browsing` requires filters and the layout to survive leaving the
 * library. iOS's `LibraryPreferencesTests` asserts the same things against a
 * private `UserDefaults` suite; this module has no Robolectric, so the store is a
 * hand-written [SharedPreferences] instead. The interface is the whole contract —
 * nothing here touches the framework, so nothing here needs a device.
 */
class LibraryPreferencesTest {

    private fun fresh() = LibraryPreferences(FakePreferences())

    @Test
    fun `filters and sorting come back on the next launch`() {
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
        assertFalse(restored.ascending)
    }

    @Test
    fun `a search term is not remembered`() {
        val preferences = fresh()

        // A filter outlives a session. A half-typed search does not, and reopening
        // the app to a library narrowed by yesterday's word reads as a bug.
        preferences.save(LibraryQuery(search = "sandman", sort = LibrarySort.SERIES))

        assertTrue(preferences.query().search.isEmpty())
        assertEquals(LibrarySort.SERIES, preferences.query().sort)
    }

    @Test
    fun `every filter group comes back, not only the three that were there first`() {
        val preferences = fresh()

        preferences.save(
            LibraryQuery(
                readStates = setOf(ReadState.FINISHED),
                formats = setOf(PublicationFormat.EPUB),
                languages = setOf("ja"),
                publishers = setOf("Fixture Press"),
                genres = setOf("Superhero"),
                tags = setOf("reprint"),
                years = YearRange(from = 1986, to = 1999),
            ),
        )

        val restored = preferences.query()
        assertEquals(setOf("ja"), restored.languages)
        assertEquals(setOf("Fixture Press"), restored.publishers)
        assertEquals(setOf("Superhero"), restored.genres)
        assertEquals(setOf("reprint"), restored.tags)
        assertEquals(YearRange(from = 1986, to = 1999), restored.years)
        assertEquals(7, restored.activeFilterCount)
    }

    @Test
    fun `a range cleared to nothing does not come back as a filter`() {
        val preferences = fresh()

        preferences.save(LibraryQuery(years = YearRange(from = 1990, to = 1999)))
        preferences.save(LibraryQuery(years = YearRange()))

        // A sentinel year would restore as a range the reader had just turned off.
        assertFalse(preferences.query().years.isActive)
        assertEquals(0, preferences.query().activeFilterCount)
    }

    @Test
    fun `one end of a stored range survives on its own`() {
        val preferences = fresh()

        preferences.save(LibraryQuery(years = YearRange(from = 1986)))

        assertEquals(YearRange(from = 1986), preferences.query().years)
    }

    @Test
    fun `the layout defaults to the grid and survives a change`() {
        val preferences = fresh()

        assertEquals(LibraryLayout.GRID, preferences.layout())
        preferences.save(LibraryLayout.LIST)
        assertEquals(LibraryLayout.LIST, preferences.layout())
    }
}
