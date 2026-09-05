package app.storyarc.feature.settings

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceDiagnosis
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.ImportedCopies
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * The source detail screen states, under its actions, what a removal deletes and what it keeps.
 *
 * `sources`, *Removing a source*: on confirmation the app removes the source "and its downloads"
 * and "retains local reading progress for those publications for 30 days". Both facts used to
 * be sentences in the confirmation's body, and on iOS the body at the largest text size stopped
 * before the thirty days with no way to scroll to them — photographed on 2026-09-05. They are a
 * footer under the actions now, read *before* the tap, on both platforms; this is the Android
 * half of `SourceDetailSizeTests/retentionIsAFooter`.
 *
 * Composed rather than asserted through a helper, for the reason [SourceProgressNoteTest]
 * composes: whether this screen draws the sentence at all can only be answered by drawing it,
 * and a test of the string alone stays green when the row is deleted from the screen.
 *
 * `GraphicsMode.NATIVE`, as in that suite, so the fit assertions measure real glyphs — and so
 * that [theFooterIsPhotographed] renders pixels rather than boxes. That case exists because the
 * device frame for this screen could not be taken: `capture-android.mjs`'s *Settings > source
 * detail* route needs a registered source and the corpus gives none, so the rendering it
 * writes under `build/reports/storyarc-captures/` is the visual record the change owes.
 */
@RunWith(RobolectricTestRunner::class)
// 34 for the reason `SourceProgressNoteTest` gives: Robolectric has no image for 37. The window
// is tall because the screen scrolls, and a footer below the fold is present and not displayed.
@Config(sdk = [34], qualifiers = "w400dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SourceRemovalFooterTest {

    @get:Rule
    val compose = createComposeRule()

    /**
     * The screen as `SettingsScreen` reaches it, for one source.
     *
     * Returns the footer's sentence so the assertions look for the shipped string in the locale
     * Robolectric was configured with, rather than for a copy of it written into this file.
     */
    private fun show(source: Source, fontScale: Float = 1f): String {
        var sentence = ""
        compose.setContent {
            sentence = stringResource(R.string.sources_remove_footer)
            CompositionLocalProvider(
                LocalDensity provides Density(density = 1f, fontScale = fontScale),
            ) {
                StoryArcTheme {
                    SourceDetailScreen(
                        source = source,
                        diagnosis = SourceDiagnosis.of(
                            source,
                            itemCount = 3,
                            downloads = emptyList(),
                            isRemovable = source.id != ImportedCopies.SOURCE_ID,
                        ),
                        onAction = {},
                        onBack = {},
                    )
                }
            }
        }
        compose.waitForIdle()
        return sentence
    }

    private fun share() = Source(
        displayName = "Attic NAS",
        kind = SourceKind.NETWORK_SHARE,
        state = SourceConnectionState.Connected,
    )

    @Test
    fun `a source the reader can remove carries the two facts under its actions`() {
        compose.onNodeWithText(show(share())).assertIsDisplayed()
    }

    @Test
    fun `on this device does not, because it cannot be removed`() {
        // The other half of the claim: a footer about removal on a screen that offers no
        // removal would describe a button that is not there. `SourceDiagnosis` withholds
        // REMOVE for the app's own imported copies, and the footer follows the action.
        val device = Source(
            id = ImportedCopies.SOURCE_ID,
            displayName = "On this device",
            kind = SourceKind.LOCAL_FOLDER,
            state = SourceConnectionState.Connected,
        )
        compose.onNodeWithText(show(device)).assertDoesNotExist()
    }

    // The footer is the longest string on this screen after the progress note and has to
    // wrap, so `design.md` §3 and §10 — every screen survives the largest accessibility text
    // size with "no clipping" — lands on it. All four shipped locales, because the length that
    // decides the wrap is different in each.

    @Test
    @Config(qualifiers = "w320dp-h1600dp")
    fun `the footer fits the narrowest window at the largest text size in English`() =
        assertTheFooterFitsTheGutter()

    @Test
    @Config(qualifiers = "de-rDE-w320dp-h1600dp")
    fun `the footer fits the narrowest window at the largest text size in German`() =
        assertTheFooterFitsTheGutter()

    @Test
    @Config(qualifiers = "es-rES-w320dp-h1600dp")
    fun `the footer fits the narrowest window at the largest text size in Spanish`() =
        assertTheFooterFitsTheGutter()

    @Test
    @Config(qualifiers = "fr-rFR-w320dp-h1600dp")
    fun `the footer fits the narrowest window at the largest text size in French`() =
        assertTheFooterFitsTheGutter()

    private fun assertTheFooterFitsTheGutter() {
        val sentence = show(share(), fontScale = LARGEST_TEXT)
        val bounds = compose.onNodeWithText(sentence).getUnclippedBoundsInRoot()
        assertTrue(
            "the footer was measured ${bounds.right - bounds.left} wide",
            bounds.right - bounds.left > Dp.Hairline,
        )
        assertTrue("the footer starts at ${bounds.left}", bounds.left >= StoryArcSpace.gutter)
        assertTrue(
            "the footer ends at ${bounds.right}, past ${WINDOW - StoryArcSpace.gutter}",
            bounds.right <= WINDOW - StoryArcSpace.gutter,
        )
    }

    // The visual record, for the frame the emulator could not take.
    //
    // Written under this module's `build/` so a run leaves it where a reader can open it and
    // nothing under version control changes; the copy filed with the other frames is made by
    // hand and named in `docs/designs/screenshots/source-lifecycle-2026-09-05/README.md`. The
    // assertion is only that a rendering exists and has pixels in it — what the pixels show is
    // for a person to look at, which is the point of a screenshot. One composition per case,
    // because a compose rule's `setContent` runs once per test.

    @Test
    fun `the footer is photographed at the default text size`() = photograph("", 1f)

    @Test
    fun `the footer is photographed at the largest text size`() = photograph("-ax", LARGEST_TEXT)

    private fun photograph(suffix: String, fontScale: Float) {
        show(share(), fontScale = fontScale)
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        val out = File("build/reports/storyarc-captures").apply { mkdirs() }
        val file = File(out, "android-settings-source-detail-footer$suffix.png")
        file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        assertTrue("${file.path} is empty", file.length() > 0)
    }

    private companion object {
        /** The narrowest window Android's compact width class allows, and so the floor. */
        val WINDOW = 320.dp

        /** The largest font scale Android's accessibility settings offer. */
        const val LARGEST_TEXT = 2f
    }
}
