package app.storyarc.core.snapshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.onRoot
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.AppearanceMode
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi
import com.github.takahirom.roborazzi.captureRoboImage
import com.github.takahirom.roborazzi.roborazziSystemPropertyOutputDirectory
import org.robolectric.RuntimeEnvironment

/**
 * The one Robolectric qualifier every catalogue snapshot uses: a phone at xhdpi.
 *
 * 411 x 891 dp at 2x is an 822 x 1782 px image, which is legible and small. A `const` so an
 * annotation can name it.
 */
const val CATALOGUE_QUALIFIERS = "w411dp-h891dp-xhdpi"

/**
 * The looks every catalogue entry is drawn in: light and dark at the default text size, and
 * light at the largest text size the system offers (font scale 2.0, `lighter-visual-check` 5.2).
 */
enum class Look(val suffix: String, val appearance: AppearanceMode, val fontScale: Float = 1f) {
    Light("light", AppearanceMode.LIGHT),
    Dark("dark", AppearanceMode.DARK),
    Largest("largest", AppearanceMode.LIGHT, fontScale = 2f),
}

/**
 * Draws [content] in the app theme, compares or records its picture as `<entry>-<look>.png` in
 * `src/test/snapshots/`, and checks it against [Accessibility]'s rules.
 *
 * [entry] is the catalogue number and name, such as `05-publication-with-cover`.
 * [knownFaults] lists a fault that stands for now, with the reason. See [KnownFault].
 * [act] gets the screen to the state the entry shows: a tap that opens a group, a scroll to a
 * section. It runs once the screen has drawn, and the picture is taken after it.
 *
 * The theme is fixed: no dynamic colour and no Natural, so the picture does not depend on a
 * wallpaper that Robolectric does not have. A reference is recorded with
 * `pnpm snap:android:record`; `pnpm snap:android` and `pnpm test:android` compare against it.
 */
@OptIn(ExperimentalRoborazziApi::class)
fun ComposeContentTestRule.catalogue(
    entry: String,
    look: Look,
    knownFaults: List<KnownFault> = emptyList(),
    act: ComposeContentTestRule.() -> Unit = {},
    content: @Composable () -> Unit,
) {
    // Before the content, so the activity's configuration carries it, and Compose scales text
    // with the platform's own non-linear curve rather than a plain multiplier.
    RuntimeEnvironment.setFontScale(look.fontScale)
    setContent {
        StoryArcTheme(appearance = look.appearance, useDynamicColor = false, natural = false) {
            Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) { content() }
        }
    }
    waitForIdle()
    act()
    waitForIdle()
    onRoot().captureRoboImage("${roborazziSystemPropertyOutputDirectory()}/$entry-${look.suffix}.png")
    assertAccessible(knownFaults.filter { it.look == null || it.look == look })
}

/** Runs [Accessibility] over what is on screen now. */
fun ComposeContentTestRule.assertAccessible(knownFaults: List<KnownFault> = emptyList()) {
    val picture = onRoot().captureToImage().asAndroidBitmap()
    val merged = onRoot().fetchSemanticsNode()
    val unmerged = onRoot(useUnmergedTree = true).fetchSemanticsNode()
    Accessibility.assertNone(Accessibility.faults(merged, unmerged, picture), knownFaults)
}
