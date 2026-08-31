package app.storyarc.feature.library

import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.persistence.LibraryPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What survives a launch, what a clear takes with it, and what arriving on the page files.
 *
 * `library-browsing`: "when a user opens search, recent queries are offered, and can be
 * cleared". Two pieces already had assertions of their own and neither covers this one:
 * `RecentSearchesTest` in `:core:model` pins the value's folding rules, and nothing knew the
 * view model existed.
 *
 * **The gap that matters is the clear.** [LibraryViewModel.clearRecentSearches] empties the
 * flow *and* writes the empty list back, and only the second half survives the launch a
 * reader takes it to be. Emptying the flow alone passes every other test in this module and
 * hands the list straight back on the next launch.
 *
 * **And the arrival.** The term is filed as it is typed — there is no submit action, so
 * there is no later moment to hang the record on — which makes every write to the query a
 * candidate for filing something. Reaching the page sets a scope or a sort and never a term,
 * and a list that grew an entry for arriving would be offering a reader their own navigation
 * back as history.
 *
 * This is the Android half of `quiet-shell-and-search` task 2.12; iOS's is
 * `RecentSearchMemoryTests.swift` and asserts the same four things in the same order. It
 * runs under Robolectric because [LibraryViewModel] takes an `Application` and
 * [LibraryPreferences] wraps `SharedPreferences` — the same reason `feature/settings`
 * already does, and strictly better than a source-level tripwire, which is what the reader
 * module has to settle for.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RecentSearchMemoryTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    /** A preferences file of its own, so one test cannot read what another wrote. */
    private fun preferences(name: String) = LibraryPreferences(
        application.getSharedPreferences("recents-$name", Context.MODE_PRIVATE),
    )

    private fun model(preferences: LibraryPreferences) =
        LibraryViewModel(application = application, preferences = preferences)

    private fun search(viewModel: LibraryViewModel, term: String) {
        viewModel.setQuery(viewModel.query.value.copy(search = term))
    }

    @Test
    fun `searches typed into one model are offered by the next`() {
        val preferences = preferences("survives")
        val first = model(preferences)
        search(first, "sandman")
        search(first, "bone")

        assertEquals(listOf("bone", "sandman"), first.recentSearches.value.terms)
        // A second model over the same store is what the next launch is.
        assertEquals(listOf("bone", "sandman"), model(preferences).recentSearches.value.terms)
    }

    @Test
    fun `clearing empties the list the next launch is offered, not only this one's`() {
        val preferences = preferences("clearing")
        val viewModel = model(preferences)
        search(viewModel, "sandman")
        search(viewModel, "bone")

        viewModel.clearRecentSearches()

        assertTrue(viewModel.recentSearches.value.terms.isEmpty())
        assertTrue(
            "The clear did not reach the store, so the next launch offers them again",
            preferences.recentSearches().terms.isEmpty(),
        )
        assertTrue(model(preferences).recentSearches.value.terms.isEmpty())
    }

    @Test
    fun `reaching the search page records nothing`() {
        val preferences = preferences("arriving")
        val viewModel = model(preferences)

        // Everything reaching the page does to the query, and nothing it does not: a sort,
        // a layout — never a term.
        viewModel.setQuery(viewModel.query.value.copy(sort = LibrarySort.SERIES))

        assertTrue("Arriving is not a search", viewModel.recentSearches.value.terms.isEmpty())
        assertTrue(preferences.recentSearches().terms.isEmpty())
    }

    @Test
    fun `leaving search does not file the empty term the shell writes on the way out`() {
        val preferences = preferences("leaving")
        val viewModel = model(preferences)
        search(viewModel, "bone")

        // Leaving the destination clears the term so the shelf landed on is not still
        // narrowed by it.
        search(viewModel, "")

        assertEquals("The term is kept as history", listOf("bone"), viewModel.recentSearches.value.terms)
        assertEquals(listOf("bone"), preferences.recentSearches().terms)
    }
}
