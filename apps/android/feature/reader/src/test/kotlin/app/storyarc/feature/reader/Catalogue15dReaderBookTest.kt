package app.storyarc.feature.reader

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import app.storyarc.core.designsystem.navigation.LocalPostureOverride
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.ShelfSettings
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Catalogue entry 15d: a right-to-left comic on a Pixel Fold held like a book (D4, 1.3, 1.4, 2.4).
 * The spread's gutter is on the fold, page 1 on the right. The posture is faked through
 * `LocalPostureOverride`.
 *
 * At xhdpi one dp is two pixels, so the fold, half way across the 841 dp display, is at 841 px.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = FoldFixtures.INNER_QUALIFIERS)
class Catalogue15dReaderBookTest {

    @get:Rule
    val compose = createComposeRule()

    @get:Rule
    val folder = TemporaryFolder()

    @Composable
    private fun Reader(model: ReaderViewModel, fold: Rect) {
        CompositionLocalProvider(LocalPostureOverride provides FoldFixtures.halfOpen(fold, isVertical = true)) {
            ReaderScreen(viewModel = model, onClose = {})
        }
    }

    private fun draw(look: Look) {
        val model = FoldFixtures.model(folder.root, ReadingDirection.RIGHT_TO_LEFT)
        val fold = Rect(841f, 0f, 841f, 1402f)
        compose.catalogue(
            "15d-reader-book-rtl",
            look,
            act = {
                loaded(model)
                waitUntil(timeoutMillis = 10_000) { shows("Page 2 of 3") }
                // A fold with no width is kept off as one pixel, so the right page starts 1 px on.
                assertEquals("The gutter is not on the fold.", fold.left, bounds("Page 2 of 3").right, 1f)
                assertEquals("The gutter is not on the fold.", fold.left, bounds("Page 1 of 3").left, 1f)
            },
        ) { Reader(model, fold) }
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)

    /**
     * A display taller than wide pairs no pages when flat. Held like a book it does, with the
     * gutter on the fold and the chrome on one side of it (1.4). The fold here has a width and is
     * not centred, so a spread of two equal halves fails this.
     */
    @Test
    @Config(qualifiers = FoldFixtures.TABLETOP_QUALIFIERS)
    fun `book posture forces the spread in portrait, with the gutter and the chrome off the fold`() {
        val model = FoldFixtures.model(folder.root, ReadingDirection.RIGHT_TO_LEFT)
        val fold = Rect(760f, 0f, 800f, 1682f)
        compose.setContent { Reader(model, fold) }
        compose.loaded(model)
        compose.waitUntil(timeoutMillis = 10_000) { compose.shows("Page 2 of 3") }

        // Right to left: page 2 is on the left of the fold, page 1 on the right.
        assertEquals(fold.left, compose.bounds("Page 2 of 3").right, 1f)
        assertEquals(fold.right, compose.bounds("Page 1 of 3").left, 1f)

        // A centre tap in reading terms: the right part of the left page.
        if (!compose.shows("Menu")) compose.onRoot().performTouchInput { click(Offset(fold.left * 0.8f, centerY)) }
        compose.waitUntil(timeoutMillis = 5_000) { compose.shows("Menu") }
        for (control in listOf("Close", "Menu")) {
            val area = compose.bounds(control)
            assertFalse("$control is under the fold: $area.", area.right > fold.left && area.left < fold.right)
        }
    }

    /** `page-transitions`, *A device that cannot curl*: no Curl row in book posture, and the stored choice kept. */
    @Test
    fun `book posture offers no curl and keeps the stored choice`() {
        val model = FoldFixtures.model(folder.root)
        val settings = ShelfSettings(transition = PageTransition.PAGE_CURL)

        val flat = model.transitions(settings, reduceMotion = false)
        val book = model.transitions(settings, reduceMotion = false, inBookPosture = true)

        assertTrue("A device that can curl offers it when flat.", PageTransition.PAGE_CURL in flat.offered)
        assertFalse("Book posture offers Curl.", PageTransition.PAGE_CURL in book.offered)
        assertTrue(book.curlIsAbsent)
        assertEquals(PageTransition.SLIDE, book.effective)
        assertEquals(PageTransition.PAGE_CURL, book.chosen)
    }
}
