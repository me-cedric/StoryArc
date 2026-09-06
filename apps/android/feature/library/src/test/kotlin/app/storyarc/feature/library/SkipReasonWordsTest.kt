package app.storyarc.feature.library

import androidx.compose.foundation.layout.Column
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
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.SkipReason
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Each refusal reaches the reader through a string resource, in the reader's own language.
 *
 * The pair to [SkipReasonCatalogueTest]: that one asserts the seven names are answerable in
 * four languages, this one asserts every case asks for one of them and that the banner draws
 * what came back.
 *
 * **The `when` in [frenchFor] is the guard, not the assertion.** It is exhaustive over
 * [SkipReason], so a case added to the format layer stops this file compiling until somebody
 * words it. That is what makes `localization`'s *Reasons of different kinds in one list*
 * enforceable: a new refusal cannot reach the notice in English while its neighbours are in
 * French.
 *
 * `GraphicsMode.NATIVE` and the 320dp window are the scaffolding `ListOrderChipsWrapTest`
 * explains: Robolectric's legacy graphics measure roughly a pixel per glyph, which makes any
 * line fit any window and any test of one pass against the defect it rejects.
 *
 * Still short of a picture. This says the sentence is laid out inside the gutter; whether it
 * reads well at the largest text size on a real device is what the capture in task 1.7 is for.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w320dp-h1600dp")
class SkipReasonWordsTest {

    @get:Rule
    val compose = createComposeRule()

    /**
     * What each refusal says in French.
     *
     * Only [SkipReason.UnsupportedFormat] binds anything, and what it binds is a format's name
     * — which `localization`'s *A sentence built around content* keeps as content: the words
     * around it are translated and the name is shown as it is. No other case carries a
     * payload, which is the whole of "the format layer stops being able to hold a sentence".
     */
    private fun frenchFor(reason: SkipReason): String = when (reason) {
        is SkipReason.UnsupportedFormat -> "StoryArc ne lit pas le format ${reason.format}"
        SkipReason.NotThere -> "le fichier est introuvable"
        SkipReason.FormatNotRecognised -> "le format n’a pas été reconnu"
        SkipReason.ArchivePasswordProtected -> "l’archive est protégée par un mot de passe"
        SkipReason.ArchiveUnreadable -> "l’archive n’a pas pu être lue"
        SkipReason.ContentProtected ->
            "ce livre audio est verrouillé par la protection de contenu de sa boutique"
        SkipReason.Unknown -> "le fichier n’a pas pu être lu"
    }

    /**
     * All seven at once, because a compose rule sets its content once.
     *
     * That is the honest shape anyway: `localization`'s *Reasons of different kinds in one
     * list* is about a list where every row is in the same language, and this is that list.
     */
    @Test
    @Config(qualifiers = "fr-rFR-w320dp-h4000dp")
    fun `every refusal is drawn in French`() =
        assertDrawn(EVERY_REASON, EVERY_REASON.map(::frenchFor))

    @Test
    fun `the longest refusal is drawn in English`() =
        assertDrawn(
            listOf(SkipReason.ContentProtected),
            listOf("this audiobook is protected by its store’s content protection"),
        )

    @Test
    @Config(qualifiers = "de-rDE-w320dp-h1600dp")
    fun `the longest refusal is drawn in German`() =
        assertDrawn(
            listOf(SkipReason.ContentProtected),
            listOf("dieses Hörbuch ist durch den Kopierschutz seines Shops gesperrt"),
        )

    /**
     * Spanish, and it is the one that matters most.
     *
     * `localization`'s *Long translations* is the scenario STATUS.md records as unsettled, and
     * Spanish — not German — is this app's measured worst case. This is the longest sentence
     * the notice can hold, in the widest language, in the narrowest window, at the largest text
     * size the accessibility settings offer.
     */
    @Test
    @Config(qualifiers = "es-rES-w320dp-h1600dp")
    fun `the longest refusal is drawn in Spanish`() =
        assertDrawn(
            listOf(SkipReason.ContentProtected),
            listOf("este audiolibro está bloqueado por la protección de contenido de su tienda"),
        )

    /**
     * Each sentence is on screen, and each is inside the gutter it is drawn in.
     *
     * Horizontal containment rather than one line: a reason that has honestly wrapped is not a
     * defect, and a reason that runs past the edge is.
     *
     * **The tree is unmerged, and that is what makes the three measurements reachable.**
     * [SkippedBanner] puts `semantics(mergeDescendants = true)` on the column holding the name
     * and the reason, so on the merged tree `onNodeWithText` answers with that column — whose
     * width is the banner's padding, never the sentence's. Measured through it, every bound
     * below held for any string of any length. `SkippedNoticeTest` names the same merge from
     * the other side: *unmerged there are two*.
     *
     * **The bounds are the row's, not the window's**, for the reason [ListOrderChipsWrapTest]
     * states: the banner pads itself by [StoryArcSpace.gutter] on both sides, so a sentence
     * that reaches [WINDOW] has already run past the edge of what it was given. Naming the
     * token rather than 280 dp keeps this following the banner if the gutter moves.
     */
    private fun assertDrawn(reasons: List<SkipReason>, expected: List<String>) {
        compose.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(density = 1f, fontScale = LARGEST_TEXT),
            ) {
                StoryArcTheme {
                    Column(modifier = Modifier.width(WINDOW)) {
                        for (reason in reasons) {
                            SkippedBanner(
                                sentence = "“refused.cb7” couldn’t be opened",
                                reason = reason,
                                onOpenList = {},
                                onDismiss = {},
                            )
                        }
                    }
                }
            }
        }
        compose.waitForIdle()

        for (sentence in expected) {
            val bounds = compose.onNodeWithText(sentence, useUnmergedTree = true)
                .getUnclippedBoundsInRoot()
            assertTrue("$sentence was measured ${bounds.right - bounds.left} wide",
                bounds.right - bounds.left > Dp.Hairline)
            assertTrue(
                "$sentence starts at ${bounds.left}",
                bounds.left >= StoryArcSpace.gutter,
            )
            assertTrue(
                "$sentence ends at ${bounds.right}",
                bounds.right <= WINDOW - StoryArcSpace.gutter,
            )
        }
    }

    private companion object {
        /** The narrowest window Android's compact width class allows, and so the floor. */
        val WINDOW = 320.dp

        /** The largest font scale Android's accessibility settings offer. */
        const val LARGEST_TEXT = 2f

        val EVERY_REASON = listOf(
            SkipReason.UnsupportedFormat("CB7"),
            SkipReason.NotThere,
            SkipReason.FormatNotRecognised,
            SkipReason.ArchivePasswordProtected,
            SkipReason.ArchiveUnreadable,
            SkipReason.ContentProtected,
            SkipReason.Unknown,
        )
    }
}
