package app.storyarc.feature.library

import android.content.res.Configuration
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import java.util.Locale
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 15.12: a reader-facing list was joined by hand with `", "`, which gives every
 * language the English convention -- no conjunction before the last item, and the wrong
 * punctuation in French and Spanish besides. `localizedList` asks
 * `android.icu.text.ListFormatter` for the composition's own locale instead.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LocalizedListTest {

    @get:Rule
    val compose = createComposeRule()

    private fun configured(locale: Locale): Configuration = Configuration().apply { setLocale(locale) }

    @Test
    fun `a two-item list takes the locale's own conjunction, not a hand-written comma`() {
        var rendered = ""
        compose.setContent {
            CompositionLocalProvider(LocalConfiguration provides configured(Locale.FRENCH)) {
                rendered = localizedList(listOf("Alice", "Bea"))
                Text(rendered)
            }
        }

        // French joins two items with "et", never a bare comma.
        compose.onNodeWithText("Alice et Bea").assertExists()
    }

    @Test
    fun `an English three-item list reads the Oxford-less English convention`() {
        compose.setContent {
            CompositionLocalProvider(LocalConfiguration provides configured(Locale.US)) {
                Text(localizedList(listOf("Alice", "Bea", "Cy")))
            }
        }

        compose.onNodeWithText("Alice, Bea, and Cy").assertExists()
    }
}
