package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.persistence.speaking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 15.7: a catalogue section's count and a scan's found count used `%1$d`, which never
 * groups, so a section or a scan of 5,000 titles read "5000 titles" rather than the locale's
 * own grouping. Both now use `%1$,d`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CountGroupingTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `a catalogue section's count is grouped in English`() {
        val resources = application.speaking("en").resources

        assertEquals(
            "5,000 titles",
            resources.getQuantityString(R.plurals.catalogue_section_count, 5_000, 5_000),
        )
    }

    @Test
    fun `a scan's found count is grouped with the German separator`() {
        val resources = application.speaking("de").resources

        assertEquals(
            "Ihre Comics werden hinzugefügt – 5.000 gefunden",
            resources.getQuantityString(R.plurals.library_scanning, 5_000, 5_000),
        )
    }
}
