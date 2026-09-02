package app.storyarc

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasStateDescription
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.playback.NowPlaying
import app.storyarc.core.playback.PlaybackDuration
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackSession
import app.storyarc.core.playback.PlaybackSpeed
import app.storyarc.core.playback.SkipIntervals
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

    @Composable
    private fun Player(
        duration: PlaybackDuration = PlaybackDuration.Known(300_000),
        sleep: SleepTimer? = null,
        fontScale: Float = 1f,
        intervals: SkipIntervals = SkipIntervals.DEFAULT,
        onIntervals: (SkipIntervals) -> Unit = {},
    ) {
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
            StoryArcTheme {
                PlayerScreen(
                    playing = playing(duration),
                    onToggle = {},
                    onSkip = {},
                    onSeek = {},
                    onChooseChapter = {},
                    onSpeed = {},
                    sleep = sleep,
                    onSleep = {},
                    onBack = {},
                    intervals = intervals,
                    onIntervals = onIntervals,
                )
            }
        }
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

    /**
     * `audio-playback`: the interval is one "the listener can configure", and it is "stated
     * on the control itself" — so the control has to state the *configured* one. A control
     * that said fifteen while the audio moved ten would be worse than one that said nothing,
     * which is why this is asserted rather than assumed from the default case above.
     */
    @Test
    fun `the skip controls state the configured interval and not the default`() {
        compose.setContent { Player(intervals = SkipIntervals.of(10, 5)) }

        compose.onNodeWithContentDescription("Back 10 seconds").assertIsDisplayed()
        compose.onNodeWithContentDescription("Forward 5 seconds").assertIsDisplayed()
        compose.onAllNodesWithContentDescription("Back 15 seconds").assertCountEquals(0)
    }

    /**
     * And the choice is reachable: four intervals a direction, each named in full.
     *
     * The chip is announced in different words from the transport control it configures —
     * "Skip forward 10 seconds" rather than "Forward 10 seconds" — which is what keeps a
     * screen reader from offering two identically named controls, only one of which moves
     * the audio.
     */
    @Test
    fun `choosing an interval reports it for that direction alone`() {
        var chosen: SkipIntervals? = null
        compose.setContent {
            Player(intervals = SkipIntervals.DEFAULT, onIntervals = { chosen = it })
        }

        compose.onNodeWithContentDescription("Skip forward 10 seconds").performClick()

        assertEquals(SkipIntervals.of(15, 10), chosen)
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

        compose.onNodeWithText("Sleep in 12:34").assertIsDisplayed()
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
        compose.onNodeWithText("15 min").assertIsDisplayed()
    }

    @Test
    fun `end of chapter is offered where the container says how long it is`() {
        compose.setContent { Player() }

        compose.onNodeWithText("End of chapter").assertIsDisplayed()
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
}
