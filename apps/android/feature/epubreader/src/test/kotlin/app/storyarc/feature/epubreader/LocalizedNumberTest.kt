package app.storyarc.feature.epubreader

import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.test.junit4.v2.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Rule
import org.junit.Test
import org.robolectric.RobolectricTestRunner
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import java.util.Locale

/**
 * Task 15.4: a contrast ratio and a slider's spoken value both called
 * `NumberFormat.getInstance()` with no locale, which reads `Locale.getDefault()` -- the
 * per-app language override does not move that. `ratio` now takes the locale directly, and
 * `spokenValue` reads `LocalConfiguration.current.locales[0]`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LocalizedNumberTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a contrast ratio uses the given locale's decimal separator`() {
        assertEquals("4.5", ratio(4.5, Locale.US))
        assertEquals("4,5", ratio(4.5, Locale.GERMANY))
        assertNotEquals(ratio(4.5, Locale.US), ratio(4.5, Locale.GERMANY))
    }

    @Test
    fun `a slider's spoken value follows the composition's own locale`() {
        var german = ""
        compose.setContent {
            val configuration = Configuration(LocalConfiguration.current).apply { setLocale(Locale.GERMANY) }
            CompositionLocalProvider(LocalConfiguration provides configuration) {
                german = spokenValue(1.25, unit = null)
            }
        }

        assertEquals("1,25", german)
    }
}
