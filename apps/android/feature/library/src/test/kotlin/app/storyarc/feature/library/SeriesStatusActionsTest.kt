package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.PublicationStatus
import app.storyarc.core.persistence.SeriesStatusStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Setting a status by hand, for a series whose source reports none.
 *
 * Asserted against the same table as iOS's `SeriesStatusActionsTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SeriesStatusActionsTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    private fun viewModel() = LibraryViewModel(application)

    private fun publication(title: String, series: String?, status: PublicationStatus? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$title"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        status = status,
        origin = MetadataOrigin.INFERRED,
    )

    private fun tearDown() {
        SeriesStatusStore.open(application).run {
            clear("Tidal Reach")
            clear("Maus")
        }
    }

    @Test
    fun `a reader-set status is offered among the available ones`() {
        tearDown()
        val model = viewModel()
        model._publications.value = listOf(publication("Tidal Reach #1", series = "Tidal Reach"))
        model.setSeriesStatus("Tidal Reach", PublicationStatus.COMPLETED)
        assertEquals(listOf(PublicationStatus.COMPLETED), model.availableStatuses())
        tearDown()
    }

    @Test
    fun `a series with a reported status is not hand-editable`() {
        val model = viewModel()
        model._publications.value = listOf(
            publication("Saga #1", series = "Saga", status = PublicationStatus.ONGOING),
        )
        assertTrue(model.seriesHasReportedStatus("Saga"))
    }

    @Test
    fun `a series with no reported status is hand-editable`() {
        val model = viewModel()
        model._publications.value = listOf(publication("Maus #1", series = "Maus"))
        assertFalse(model.seriesHasReportedStatus("Maus"))
    }

    @Test
    fun `clearing a hand-set status removes it from what is available`() {
        tearDown()
        val model = viewModel()
        model._publications.value = listOf(publication("Maus #1", series = "Maus"))
        model.setSeriesStatus("Maus", PublicationStatus.COMPLETED)
        model.clearSeriesStatus("Maus")
        assertTrue(model.availableStatuses().isEmpty())
        tearDown()
    }

    @Test
    fun `manualStatus reads back exactly what was set, and null once cleared`() {
        tearDown()
        val model = viewModel()
        model._publications.value = listOf(publication("Tidal Reach #1", series = "Tidal Reach"))
        assertEquals(null, model.manualStatus("Tidal Reach"))
        model.setSeriesStatus("Tidal Reach", PublicationStatus.HIATUS)
        assertEquals(PublicationStatus.HIATUS, model.manualStatus("Tidal Reach"))
        model.clearSeriesStatus("Tidal Reach")
        assertEquals(null, model.manualStatus("Tidal Reach"))
        tearDown()
    }

    @Test
    fun `setting a status by hand reaches what the shelf actually filters to`() {
        tearDown()
        val model = viewModel()
        model._publications.value = listOf(
            publication("Tidal Reach #1", series = "Tidal Reach"),
            publication("Maus #1", series = "Maus"),
        )
        model.setSeriesStatus("Tidal Reach", PublicationStatus.COMPLETED)
        model.setQuery(model.query.value.copy(statuses = setOf(PublicationStatus.COMPLETED)))
        assertEquals(listOf("Tidal Reach #1"), model.visible.value.map { it.displayTitle })
        tearDown()
    }
}
