package app.storyarc

import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasStateDescription
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.playback.NowPlaying
import app.storyarc.core.playback.PlaybackDuration
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackSession
import app.storyarc.core.playback.PlaybackSpeed
import app.storyarc.core.playback.SleepAfter
import app.storyarc.core.playback.SleepTimer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Reaching the player without sight, and reading it at the largest text size.
 *
 * `audio-playback`, *Labels and values*:
 *
 * > **THEN** it is announced with a name and, where it carries one, its value — the speed,
 * > the skip interval, the remaining sleep time, the position
 * > **AND** the scrub control is announced as an adjustable with its position stated in
 * > time, not as a percentage
 *
 * and *At the largest text size*: "the publication, the chapter and every stated value are
 * readable in full, the surface scrolls if it must, and no transport control is pushed off
 * the screen".
 *
 * Robolectric with `GraphicsMode.NATIVE`, for the reason `CompactPlayerTest` sets out at
 * length: legacy graphics measure a glyph at about a pixel wide, so a suite run that way
 * would pass against a control drawn off the edge of the window.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37. A phone window, because it is the narrowest case.
@Config(sdk = [34], qualifiers = "w360dp-h740dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PlayerSemanticsTest {

    @get:Rule
    val compose = createComposeRule()

    private fun playing(duration: PlaybackDuration = PlaybackDuration.Known(300_000)) = NowPlaying(
        publicationId = "sea-room",
        title = "Sea Room",
        parts = listOf(PlaybackPart("The Shiants", duration), PlaybackPart("Bird Island", duration)),
        partIndex = 0,
        offsetMillis = 42_000,
        session = PlaybackSession().started(),
        speed = PlaybackSpeed.of(1.4),
    )

    /** The corpus's chaptered M4B as the library describes it: an audiobook with no cover. */
    private fun audiobook() = Publication(
        identity = PublicationIdentity(normalizedPath = "/audiobooks/sea-room.m4b"),
        format = PublicationFormat.M4B,
        displayTitle = "Sea Room",
        origin = MetadataOrigin.INFERRED,
    )

    @Composable
    private fun Player(
        duration: PlaybackDuration = PlaybackDuration.Known(300_000),
        sleep: SleepTimer? = null,
        fontScale: Float = 1f,
        publication: Publication? = audiobook(),
        cover: suspend (Publication, Int) -> Bitmap? = { _, _ -> null },
    ) {
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
            StoryArcTheme {
                PlayerScreen(
                    playing = playing(duration),
                    onToggle = {},
                    onSkip = {},
                    onSeek = {},
                    onSeekSettled = {},
                    onChooseChapter = {},
                    onSpeed = {},
                    sleep = sleep,
                    onSleep = {},
                    onBack = {},
                    publication = publication,
                    cover = cover,
                )
            }
        }
    }

    // MARK: 4.4b / 4.5 — the artwork

    /**
     * `audio-playback`, *A publication with no cover*: the player "draws the same coverless
     * treatment every other surface draws … rather than a treatment of the player's own".
     *
     * The well is what says the format — nothing else on this screen names `M4B` — so the
     * format in the drawn tree is the well being there. The title is expected **twice** in the
     * unmerged tree, the top bar's and the well's, exactly as `DownloadsCoverlessWellTest`
     * expects it twice on the Downloads cell for the same reason. Unmerged, because the well is
     * deliberately silent to a screen reader; what is asserted here is what was drawn.
     */
    @Test
    fun `a book with no cover draws the shared well, naming its format`() {
        compose.setContent { Player(cover = { _, _ -> null }) }

        compose.onNodeWithText("M4B", useUnmergedTree = true).assertIsDisplayed()
        compose.onAllNodesWithText("Sea Room", useUnmergedTree = true).assertCountEquals(2)
        // And the well is silent: to a screen reader the title is the top bar's alone, and the
        // format is nobody's — the well's own contract, held here for the surface that draws it.
        compose.onAllNodesWithText("Sea Room").assertCountEquals(1)
        compose.onAllNodesWithText("M4B").assertCountEquals(0)
    }

    /**
     * *The full player* "shows the cover". A cover is pixels and has no semantics — the
     * description is null on purpose, see the test below — so this reads the pixels: the
     * artwork sits first in the column under a 64 dp bar and 16 dp of padding, at most 320 dp
     * wide and square, and a cover letterboxed into that square covers its centre. A red
     * bitmap is handed over as the cover, and the centre had better be red.
     */
    @Test
    fun `a book with a cover draws the cover and not the well`() {
        val red = Bitmap.createBitmap(20, 30, Bitmap.Config.ARGB_8888).apply {
            eraseColor(AndroidColor.RED)
        }
        compose.setContent { Player(cover = { _, _ -> red }) }
        compose.waitForIdle()

        compose.onAllNodesWithText("M4B", useUnmergedTree = true).assertCountEquals(0)
        val pixels = compose.onRoot().captureToImage().toPixelMap()
        val side = minOf(ARTWORK_MAX_WIDTH_PX, pixels.width - 2 * PAGE_PADDING_PX)
        val left = (pixels.width - side) / 2
        val top = TOP_BAR_PX + PAGE_PADDING_PX
        val centre = pixels[left + side / 2, top + side / 2]
        assertEquals(
            "the centre of the artwork is not the cover's red but ${Integer.toHexString(centre.toArgb())}",
            Color.Red.toArgb(),
            centre.toArgb(),
        )
    }

    /**
     * `audio-playback`'s *Labels and values* wants each thing announced once. The top bar
     * names the book, so a cover adds nothing: an `Image` with a description would have TalkBack
     * say *Sea Room* twice on a screen whose whole point is what is being said. The coverless
     * half of the same rule is the well's own contract, asserted with the well above.
     */
    @Test
    fun `the artwork names nothing twice to a screen reader`() {
        val cover = Bitmap.createBitmap(20, 30, Bitmap.Config.ARGB_8888)
        compose.setContent { Player(cover = { _, _ -> cover }) }
        compose.waitForIdle()

        compose.onAllNodesWithText("Sea Room").assertCountEquals(1)
        compose.onAllNodesWithContentDescription("Sea Room").assertCountEquals(0)
    }

    // MARK: 8.1 — a name, and a value where there is one

    @Test
    fun `the skip controls are named for what they do and how far`() {
        compose.setContent { Player() }

        // One element each, named for the whole gesture rather than read out as an arrow and
        // a loose number.
        compose.onNodeWithContentDescription("Back 15 seconds").assertIsDisplayed()
        compose.onNodeWithContentDescription("Forward 30 seconds").assertIsDisplayed()
    }

    @Test
    fun `the speed control announces the number rather than a percentage`() {
        compose.setContent { Player() }

        // "62 per cent" of a speed control tells a listener nothing they can act on.
        assertTrue(
            "no control states the speed as its value",
            compose.onAllNodes(hasStateDescription("1.4×")).fetchSemanticsNodes().isNotEmpty(),
        )
    }

    @Test
    fun `the scrub control states its position in time`() {
        compose.setContent { Player() }

        assertTrue(
            "the scrub control does not state a time, so it states a percentage",
            compose.onAllNodes(hasStateDescription("0:42 of 5:00")).fetchSemanticsNodes().isNotEmpty(),
        )
    }

    /** The remaining sleep time is one of the four values the requirement names. */
    @Test
    fun `a running sleep timer states how long is left`() {
        compose.setContent {
            Player(sleep = SleepTimer(SleepAfter.Duration(900_000), 754_000))
        }

        compose.onNodeWithText("Sleep in 12:34").performScrollTo().assertIsDisplayed()
    }

    // MARK: absent rather than refusing

    /**
     * `audio-playback`: "every control the player offers works, or is absent — none is
     * present and refusing".
     *
     * A part with no stated duration has no end of chapter to stop at, so the option is not
     * drawn. The durations still are.
     */
    @Test
    fun `end of chapter is not offered where nothing knows how long the chapter is`() {
        compose.setContent { Player(duration = PlaybackDuration.Estimated(300_000)) }

        compose.onNodeWithText("End of chapter").assertDoesNotExist()
        compose.onNodeWithText("15 min").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun `end of chapter is offered where the container says how long it is`() {
        compose.setContent { Player() }

        compose.onNodeWithText("End of chapter").performScrollTo().assertIsDisplayed()
    }

    // MARK: 8.4 — the largest text size

    /**
     * The transport stays on screen and the sleep options wrap rather than running off it.
     *
     * The chapter list is what scrolls away, which is why the transport sits above it.
     */
    @Test
    fun `at the largest text size the transport is still on screen`() {
        val scale = mutableFloatStateOf(1f)
        compose.setContent { Player(fontScale = scale.floatValue) }

        scale.floatValue = 2f
        compose.waitForIdle()

        compose.onNodeWithContentDescription("Back 15 seconds").assertIsDisplayed()
        compose.onNodeWithContentDescription("Forward 30 seconds").assertIsDisplayed()
        compose.onNodeWithContentDescription("Pause").assertIsDisplayed()
    }

    /**
     * Two nodes name the chapter — the heading above the transport and its row in the
     * chapter list — and this is about the heading, which is above the fold.
     */
    @Test
    fun `at the largest text size the chapter is readable in full`() {
        compose.setContent { Player(fontScale = 2f) }

        compose.onAllNodesWithText("The Shiants").onFirst().assertIsDisplayed()
    }

    private companion object {
        /** `PlayerArtwork`'s cap, in the test's mdpi pixels, where one dp is one pixel. */
        const val ARTWORK_MAX_WIDTH_PX = 320

        /** The column's horizontal and vertical padding. */
        const val PAGE_PADDING_PX = 16

        /** Material's small top app bar, which is the player's. */
        const val TOP_BAR_PX = 64
    }
}
