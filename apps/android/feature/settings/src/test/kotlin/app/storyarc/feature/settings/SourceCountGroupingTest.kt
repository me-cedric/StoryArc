package app.storyarc.feature.settings

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.persistence.speaking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 15.7: a source's title count used `%1$d`, which never groups, so a source of 5,000
 * titles read "5000 titles" rather than the locale's own grouping. `sources_detail` and
 * `sources_detail_progress` now use `%1$,d`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SourceCountGroupingTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `a source's title count is grouped in English`() {
        val resources = application.speaking("en").resources

        assertEquals(
            "5,000 titles",
            resources.getQuantityString(R.plurals.sources_detail, 5_000, 5_000),
        )
    }

    @Test
    fun `a source's title count is grouped with the German separator`() {
        val resources = application.speaking("de").resources

        assertEquals(
            "5.000 Titel",
            resources.getQuantityString(R.plurals.sources_detail, 5_000, 5_000),
        )
    }

    @Test
    fun `a partial sync's progress groups both numbers`() {
        val resources = application.speaking("en").resources

        assertEquals(
            "1,200 of 5,000 titles",
            resources.getQuantityString(R.plurals.sources_detail_progress, 5_000, 1_200, 5_000),
        )
    }
}
