package app.storyarc.core.snapshots

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.ColorPainter
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The accessibility rules that every catalogue entry runs are real: each of these faults fails
 * them. If a change to [Accessibility] stops one of these from failing, the catalogue has
 * stopped protecting that rule, and this is where it shows.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class AccessibilityChecksTest {

    @get:Rule
    val compose = createComposeRule()

    private fun failureOf(content: @Composable () -> Unit): String {
        compose.setContent(content)
        compose.waitForIdle()
        return assertThrows(AssertionError::class.java) { compose.assertAccessible() }.message.orEmpty()
    }

    @Test
    fun `a 40 dp clickable fails`() {
        // Compose widens a clickable to 48 dp for the finger and the accessibility service
        // reports the widened area, so a 40 dp clickable fails only where that is switched off.
        val message = failureOf {
            val base = LocalViewConfiguration.current
            val noWidening = object : ViewConfiguration by base {
                override val minimumTouchTargetSize = DpSize.Zero
            }
            CompositionLocalProvider(LocalViewConfiguration provides noWidening) {
                Box(Modifier.size(40.dp).background(Color.Blue).clickable {}) { Text("Go", color = Color.White) }
            }
        }

        assertTrue(message, message.contains("TOUCH_TARGET") && message.contains("40.0 x 40.0"))
    }

    @Test
    fun `a 40 dp clickable that Compose widens to 48 dp passes`() {
        compose.setContent {
            Box(Modifier.size(40.dp).background(Color.Blue).clickable {}) { Text("Go", color = Color.White) }
        }
        compose.waitForIdle()

        compose.assertAccessible()
    }

    @Test
    fun `a clickable image with no label fails`() {
        val message = failureOf {
            Image(ColorPainter(Color.Blue), contentDescription = null, Modifier.size(48.dp).clickable {})
        }

        assertTrue(message, message.contains("LABEL"))
    }

    @Test
    fun `text with low contrast fails`() {
        val message = failureOf {
            Box(Modifier.background(Color.White)) { Text("Faint", color = Color(0xFFDDDDDD)) }
        }

        assertTrue(message, message.contains("CONTRAST") && message.contains("Faint"))
    }

    @Test
    fun `a fault that is listed is accepted and a stale entry is an error`() {
        compose.setContent {
            Box(Modifier.background(Color.White)) { Text("Faint", color = Color(0xFFDDDDDD)) }
        }
        compose.waitForIdle()
        val known = KnownFault(Check.CONTRAST, "Faint", "the fixture is faint on purpose")

        compose.assertAccessible(listOf(known))
        val stale = assertThrows(AssertionError::class.java) {
            compose.assertAccessible(listOf(known, KnownFault(Check.LABEL, "Gone", "no longer occurs")))
        }
        assertTrue(stale.message.orEmpty().contains("no longer occur"))
    }
}
