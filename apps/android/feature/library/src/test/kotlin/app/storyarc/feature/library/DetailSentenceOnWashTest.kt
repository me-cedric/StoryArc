package app.storyarc.feature.library

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.model.CoverColours
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.UUID

/**
 * `close-the-audited-gaps` 25.3: the sentence under *Download it* on a Kavita title page had
 * almost no contrast on the dark wash. The wash is dark in every appearance, and the sentence
 * was drawn in the app's own secondary ink, which in the light appearance is dark too.
 *
 * Read off the pixels of the sentence, because its colour is a parameter of a `Text` and no
 * semantics property states it.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class DetailSentenceOnWashTest {

    @get:Rule
    val compose = createComposeRule()

    private val wash = "#4F5766"

    private val SOURCE = UUID.nameUUIDFromBytes("kavita".toByteArray())

    private val row = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(sourceId = SOURCE, remoteId = "42"),
        ),
        format = PublicationFormat.EPUB,
        displayTitle = "The Long Field",
        origin = MetadataOrigin.AUTHORITATIVE,
        sourceId = SOURCE,
    )

    private fun luminance(color: Color): Double {
        fun channel(value: Float): Double =
            value.toDouble().let { if (it <= 0.03928) it / 12.92 else Math.pow((it + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    private fun contrast(a: Color, b: Color): Double {
        val one = luminance(a)
        val two = luminance(b)
        return (maxOf(one, two) + 0.05) / (minOf(one, two) + 0.05)
    }

    /** The most contrast any pixel of the sentence has against the wash behind it. */
    private fun inkOn(appearance: AppearanceMode): Double {
        val accent = detailAccentOf(CoverColours(wash = wash, accent = "#B7C4E0", onAccent = "#000000"))
        compose.setContent {
            StoryArcTheme(appearance = appearance, useDynamicColor = false) {
                DetailMainPane(
                    publication = row,
                    cover = null,
                    accent = accent,
                    hero = DetailHeroLayout(isSideBySide = false, coverHeight = 120.dp),
                    action = PrimaryAction.NEEDS_DOWNLOAD,
                    provenance = Provenance(
                        place = Provenance.Place.LIBRARY,
                        libraryName = "Beach Library",
                        readiness = Provenance.Readiness.NOT_DOWNLOADED,
                        alsoIn = null,
                    ),
                    onRead = {},
                    onDownload = {},
                )
            }
        }
        compose.waitForIdle()
        val sentence = compose.onNodeWithText("This cannot be opened", substring = true)
        val map = sentence.captureToImage().toPixelMap()
        val ground = map[0, 0]
        var best = 1.0
        for (x in 0 until map.width) for (y in 0 until map.height) best = maxOf(best, contrast(map[x, y], ground))
        return best
    }

    @Test
    fun `the sentence is legible on the wash in the light appearance`() {
        val ratio = inkOn(AppearanceMode.LIGHT)
        assertTrue("the sentence reaches only $ratio:1", ratio >= 4.5)
    }

    @Test
    fun `the sentence is legible on the wash in the dark appearance`() {
        val ratio = inkOn(AppearanceMode.DARK)
        assertTrue("the sentence reaches only $ratio:1", ratio >= 4.5)
    }

    @Test
    fun `the colour written on a wash is derived from the wash`() {
        assertEquals(Color.White, onWashOf(Color(0xFF4F5766)))
        assertEquals(Color.Black, onWashOf(Color(0xFFF2D98C)))
    }
}
