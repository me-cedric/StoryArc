package app.storyarc.feature.library

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.cover.CoverlessWell
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A cover-shaped cell with no artwork in it says what the publication is, and stays inside its
 * own box while it does.
 *
 * Three things are pinned here and they are different things. The well's own contract — a title
 * always, a format only when the surface names one — is asserted against [CoverlessWell]
 * directly. The well's *layout* is measured at three text sizes, because a title centred in the
 * whole well with the format laid on top of it is clear at the default size and was not clear
 * above it. And [HomeCoverArt] is composed as one of the three surfaces that ended at
 * `cover?.let { Image(…) }` with no else branch, so it drew the sunken surface and stopped.
 *
 * Every text lookup uses the **unmerged** tree, because the well is deliberately silent to a
 * screen reader: `CoverlessWell` clears its own semantics, so the caption or the
 * `contentDescription` its caller already carries is the one thing spoken. What these tests
 * claim is what is *drawn*, and the unmerged tree is where that lives. The spoken half is
 * `:app`'s `DownloadsCoverlessWellTest`, on the cell whose announcement the clear was for.
 *
 * The Downloads shelf — the surface the defect was reported on — is covered there too, and no
 * longer only by a source grep: `:app` declares Robolectric and a Compose test rule now, which
 * is what a mutation reinstating that shelf's blank well needed in order to fail.
 *
 * `GraphicsMode.NATIVE` for the reason `ListOrderChipsWrapTest` gives at length: Robolectric's
 * legacy graphics measure a string as roughly a pixel per glyph, which makes text fit anywhere
 * and any assertion about it pass. The cell is given a real cover's width and proportion so
 * the title has somewhere plausible to wrap.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above this app's minimum, and nothing here has
// an API level in it.
@Config(sdk = [34])
class CoverlessWellTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a well names the publication`() {
        showWell(title = SHORT_TITLE, format = "CBZ")

        compose.onNodeWithText(SHORT_TITLE, useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    fun `a well names the format when the surface asks for it`() {
        showWell(title = SHORT_TITLE, format = "CBZ")

        compose.onNodeWithText("CBZ", useUnmergedTree = true).assertIsDisplayed()
    }

    /**
     * And says nothing about a format on a surface that passes none.
     *
     * This is the whole of what the parameter buys. A shelf of one series, or a Home card whose
     * caption is the title and how much is left, gains nothing from a label every cell around
     * it repeats — so the parameter has to be able to withhold it, not merely soften it.
     */
    @Test
    fun `a well with no format names none`() {
        showWell(title = SHORT_TITLE, format = null)

        compose.onNodeWithText("CBZ", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithText(SHORT_TITLE, useUnmergedTree = true).assertIsDisplayed()
    }

    /**
     * The title never reaches the format label, at any text size the app supports.
     *
     * This is the defect the well inherited from the library shelf and then spread to Downloads
     * by being shared: the title was centred in the whole well and the label was drawn on top
     * of it, so from `font_scale 1.5` up the title's last line was set underneath the label.
     * `font_scale 1.5` on the Downloads shelf is a configuration this repository photographs —
     * `docs/designs/screenshots/after-2026-08-31b/android-downloads-tablet-scale15-light.png`.
     *
     * Measured rather than reasoned about: the numbers in the failure message are the node
     * positions, so a change to a text role or a token is caught by arithmetic that is done
     * here rather than in a comment. 2.0 is the top of `font_scale`'s range in the captures.
     */
    @Test
    fun `a well keeps its title clear of the format label at every text size`() {
        var asked by mutableStateOf(1f)
        compose.setContent {
            val device = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(density = device.density, fontScale = asked),
            ) {
                StoryArcTheme {
                    Box(modifier = Modifier.width(COVER_WIDTH).aspectRatio(2f / 3f)) {
                        CoverlessWell(title = LONG_TITLE, format = "CBZ")
                    }
                }
            }
        }

        for (scale in listOf(1f, 1.5f, 2f)) {
            compose.runOnIdle { asked = scale }
            compose.waitForIdle()

            val title = extent(LONG_TITLE)
            val label = extent("CBZ")
            assertTrue(
                "at font scale $scale the title runs to ${title.second} px and the label " +
                    "starts at ${label.first} px",
                title.second <= label.first,
            )
        }
    }

    /**
     * Home's card, with no artwork to draw. The title is on screen and no format is.
     *
     * `cover` returns `null` for every request, which is what a publication with no cover does
     * forever — `LibraryViewModel.cover` answers `null` for one, and the card is redrawn with
     * that answer on every recomposition. Before this change the box was empty.
     *
     * The format assertion is the other half, and it is not decoration: `format` is the one
     * parameter the four surfaces differ about, and passing Home the format instead of `null`
     * compiled and passed everything. Nothing on Home names a format, so the well must not.
     */
    @Test
    fun `home's cover art draws the well when there is no artwork and names no format`() {
        compose.setContent {
            StoryArcTheme {
                HomeCoverArt(
                    publication = publication(SHORT_TITLE),
                    cover = { _, _ -> null },
                    width = COVER_WIDTH,
                    modifier = Modifier.width(COVER_WIDTH).aspectRatio(2f / 3f),
                )
            }
        }

        compose.onNodeWithText(SHORT_TITLE, useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText(FORMAT, useUnmergedTree = true).assertDoesNotExist()
    }

    /** Where a drawn text runs from and to, down the root, in pixels. Unclipped. */
    private fun extent(text: String): Pair<Float, Float> {
        val node = compose.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode()
        val top = node.positionInRoot.y
        return top to top + node.size.height
    }

    private fun showWell(title: String, format: String?) {
        compose.setContent {
            StoryArcTheme {
                // The frame the callers own: every one of the four already has a cover-shaped
                // box at the sunken surface, and the well paints only its contents.
                Box(modifier = Modifier.width(COVER_WIDTH).aspectRatio(2f / 3f)) {
                    CoverlessWell(title = title, format = format)
                }
            }
        }
    }

    private fun publication(title: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
    )

    private companion object {
        const val SHORT_TITLE = "Foreign Codec"

        /** Long enough to fill the well at the default text size, so the bound is exercised. */
        const val LONG_TITLE = "Foreign Codec of the Northern Harbour Lights Annual"

        val FORMAT = PublicationFormat.CBZ.displayName

        /** `design.md` §4's phone tier, so a title wraps against a width the app really uses. */
        val COVER_WIDTH = 104.dp
    }
}
