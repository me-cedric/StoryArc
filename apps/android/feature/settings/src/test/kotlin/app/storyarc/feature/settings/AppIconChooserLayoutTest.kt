package app.storyarc.feature.settings

import android.content.ComponentName
import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.AppIconChoice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The icon chooser survives the largest text size, in the smallest window this app supports.
 *
 * `settings-and-about`, *At the largest text size*: "every option's name is readable in full
 * and its tile is still large enough to tell the faces apart, the list scrolling if it must".
 *
 * Two of Material's own rules are what the row is built to satisfy, and they pull against each
 * other: support 200% text, and do not resize a component that contains no text. So the tile
 * is a fixed number of dp and the name beside it grows. Get it the other way round and at 200%
 * the tile takes a third of a 320 dp line and the name is measured into what is left — the
 * failure `WhatsNewLayoutTest` was written for one screen over, and the reason `AppIconGroup`
 * states the 56 dp in a named value rather than in the row.
 *
 * **The five components are registered with the platform first.** The tile is the component's
 * own launcher drawable, asked of `PackageManager`; off a device nothing is installed, so the
 * row draws no tile at all and a measurement of the tile column would measure nothing. A
 * registered component answers with the default application icon, which is a real drawable of
 * the size the row asks for and is all this suite needs.
 *
 * iOS has no host-runnable equivalent: the chooser's tile is a `UIImage` from the app bundle
 * and `swift test` runs with no simulator. `ios-app-icon-chooser-ax5.png` is its half.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34], qualifiers = "w320dp-h640dp")
class AppIconChooserLayoutTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private fun name(face: AppIconChoice): String = context.getString(face.labelRes)

    /** A device with the five aliases installed, so every row has a tile to draw. */
    @Before
    fun installTheAliases() {
        val packages = Shadows.shadowOf(context.packageManager)
        AppIconChoice.entries.forEach { face ->
            packages.addActivityIfNotPresent(
                ComponentName(context.packageName, face.componentClassName),
            )
        }
    }

    /**
     * The text size, as state rather than an argument.
     *
     * `setContent` may be called once per rule, and the tests below measure the same chooser at
     * two sizes — which is also how a reader changes it: by moving a slider while the app runs.
     */
    private val fontScale = mutableFloatStateOf(1f)
    private var composed = false

    private fun show(fontScale: Float) {
        this.fontScale.floatValue = fontScale
        if (!composed) {
            composed = true
            compose.setContent { chooser() }
        }
        compose.waitForIdle()
    }

    @Composable
    private fun chooser() {
        CompositionLocalProvider(
            LocalDensity provides Density(density = 1f, fontScale = fontScale.floatValue),
        ) {
            StoryArcTheme {
                Box(modifier = Modifier.size(WINDOW, WINDOW_HEIGHT)) { AppIconGroup() }
            }
        }
    }

    /** The unmerged node carrying one face's name. A row merges, and a merged row is the width. */
    private fun nameBounds(face: AppIconChoice) =
        compose.onNodeWithText(name(face), useUnmergedTree = true).getUnclippedBoundsInRoot()

    @Test
    fun `every face's name keeps most of the line at the largest text size`() {
        show(fontScale = LARGEST_TEXT)

        AppIconChoice.entries.forEach { face ->
            val bounds = nameBounds(face)
            // What is left of the line once the radio, the tile and the gutters have taken
            // theirs. The name wraps into it, so this is the width a long name would have —
            // and anything under half the window has been squeezed rather than laid out.
            val remaining = WINDOW - bounds.left
            assertTrue("${face.name} is left $remaining of the line", remaining > WINDOW / 2)
            assertTrue("${face.name} ends at ${bounds.right}, past $WINDOW", bounds.right <= WINDOW)
        }
    }

    @Test
    fun `every face's name grows with the reader's text`() {
        show(fontScale = 1f)
        val atDefault = AppIconChoice.entries.associateWith { nameBounds(it).let { b -> b.bottom - b.top } }
        show(fontScale = LARGEST_TEXT)

        AppIconChoice.entries.forEach { face ->
            val grown = nameBounds(face).let { it.bottom - it.top }
            // A row of a fixed height would clip the name instead of growing, and a clipped
            // name is still laid out — it is only unreadable.
            assertTrue(
                "${face.name} is ${atDefault[face]} tall by default and $grown at 200%",
                grown > atDefault.getValue(face),
            )
        }
    }

    @Test
    fun `the tile column does not grow with the text size`() {
        show(fontScale = 1f)
        val atDefault = nameBounds(AppIconChoice.entries.first()).left
        show(fontScale = LARGEST_TEXT)
        val atLargest = nameBounds(AppIconChoice.entries.first()).left

        // Measured as where the name *starts*, which is the radio plus the tile plus the
        // gutters and needs nothing added to the chooser for a test to hold on to.
        assertEquals(
            "The name column starts at $atDefault by default and $atLargest at 200%",
            atDefault,
            atLargest,
        )
    }

    @Test
    fun `a tile stays large enough to tell the faces apart`() {
        // Measured as the row's own height, which is what a 56 dp tile sets: the radio is
        // 48 dp and the name is smaller still, so a row shorter than the tile is a row whose
        // tile shrank or went missing. A face a reader cannot see is not a face they can pick.
        show(fontScale = 1f)
        AppIconChoice.entries.forEach { face ->
            val row = compose.onNodeWithText(name(face)).getUnclippedBoundsInRoot()
            val height = row.bottom - row.top
            assertTrue("${face.name}'s row is only $height tall", height >= TILE_SIDE)
        }

        show(fontScale = LARGEST_TEXT)
        AppIconChoice.entries.forEach { face ->
            val row = compose.onNodeWithText(name(face)).getUnclippedBoundsInRoot()
            val height = row.bottom - row.top
            assertTrue("${face.name}'s row is only $height tall at 200%", height >= TILE_SIDE)
        }
    }

    private companion object {
        /** The narrowest window Android's compact width class allows, and so the floor. */
        val WINDOW = 320.dp

        /** A short window, because a chooser that fits a tall one proves nothing. */
        val WINDOW_HEIGHT = 640.dp

        /**
         * The side `AppIconGroup` draws a tile at, named here rather than shared.
         *
         * Sharing it would make this suite assert a constant against itself. Written out, the
         * row has to be at least this tall for a reason a reader can state: the tile is the
         * picture, and the spec asks for it to stay large enough to tell the faces apart.
         */
        val TILE_SIDE: Dp = 56.dp

        /** The largest font scale Android's accessibility settings offer. */
        const val LARGEST_TEXT = 2f
    }
}
