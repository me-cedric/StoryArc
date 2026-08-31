package app.storyarc.feature.library

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
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
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.KavitaCard
import app.storyarc.core.persistence.KavitaCardStore
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The two lines a downloaded Kavita title states, in every language this app ships, in the
 * narrowest window, at the largest text size.
 *
 * `KavitaCardFactsTest` asserts the English literals and nothing else, which leaves two
 * things unsaid. The lines could be drawn from a hardcoded English string and pass it: the
 * status is one of five translated names inside a translated frame, and only reading the
 * French line proves the frame and the name both came from `values-fr`. And the widest case
 * is not English -- `Classification par âge : Adults Only 18+` is roughly forty characters
 * before the reader has asked for larger text.
 *
 * The rating's own label is deliberately untranslated: it is ComicInfo.xml v2.1's own
 * vocabulary, half of it codes, and a paraphrased rating is a rating no body gave. So only
 * the words introducing it change between locales, and that is what these assertions say.
 *
 * `GraphicsMode.NATIVE` and the tall window are the scaffolding `ListOrderChipsWrapTest`
 * explains: Robolectric's legacy graphics measure roughly a pixel per glyph, which makes any
 * line fit any window and any test of one pass against the defect it rejects.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports.
@Config(sdk = [34], qualifiers = "w320dp-h1600dp")
class KavitaCardFactsLocaleTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `both lines are drawn in English`() =
        assertLinesFit("Status: Completed", "Age rating: Adults Only 18+")

    @Test
    @Config(qualifiers = "de-rDE-w320dp-h1600dp")
    fun `both lines are drawn in German`() =
        assertLinesFit("Status: Abgeschlossen", "Altersfreigabe: Adults Only 18+")

    @Test
    @Config(qualifiers = "es-rES-w320dp-h1600dp")
    fun `both lines are drawn in Spanish`() =
        assertLinesFit("Estado: Finalizada", "Clasificación por edad: Adults Only 18+")

    @Test
    @Config(qualifiers = "fr-rFR-w320dp-h1600dp")
    fun `both lines are drawn in French`() =
        assertLinesFit("Statut : Terminée", "Classification par âge : Adults Only 18+")

    /**
     * Each line is on screen in the reader's own language, and inside the column it is drawn
     * in.
     *
     * Horizontal containment rather than a single line each: a caption that has honestly
     * wrapped is not a defect, and a caption that runs past the gutter is.
     */
    private fun assertLinesFit(status: String, rating: String) {
        // Kavita's own numbers: 2 is `Completed` and 13 is `Adults Only 18+`, the widest label
        // in its table.
        KavitaCardStore.open(ApplicationProvider.getApplicationContext()).save(
            KavitaCard(
                publicationId = "p1",
                downloadId = "d1",
                sourceId = "s",
                seriesId = 7,
                chapterId = 1,
                seriesName = "Tidal Reach",
                chapterName = "The Harbour",
                ageRating = 13,
                publicationStatus = 2,
            ),
        )

        compose.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(density = 1f, fontScale = LARGEST_TEXT),
            ) {
                StoryArcTheme {
                    Column(
                        modifier = Modifier
                            .width(WINDOW)
                            .padding(horizontal = StoryArcSpace.gutter),
                    ) {
                        KavitaCardFacts("p1")
                    }
                }
            }
        }
        compose.waitForIdle()

        listOf(status, rating).forEach { line ->
            val bounds = compose.onNodeWithText(line).getUnclippedBoundsInRoot()
            assertTrue("$line was measured ${bounds.right - bounds.left} wide",
                bounds.right - bounds.left > Dp.Hairline)
            assertTrue("$line starts at ${bounds.left}", bounds.left >= StoryArcSpace.gutter)
            assertTrue("$line ends at ${bounds.right}",
                bounds.right <= WINDOW - StoryArcSpace.gutter)
        }
    }

    private companion object {
        /** The narrowest window Android's compact width class allows, and so the floor. */
        val WINDOW = 320.dp

        /** The largest font scale Android's accessibility settings offer. */
        const val LARGEST_TEXT = 2f
    }
}
