package app.storyarc

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.playback.NowPlaying
import app.storyarc.core.playback.PlaybackDuration
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackSession
import app.storyarc.core.playback.PlaybackSpeed
import app.storyarc.core.playback.SleepAfter
import app.storyarc.core.playback.SleepTimer
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Task 24.4 and 24.5 of `close-the-audited-gaps`: every sleep-timer chip is a touch target of
 * 48 x 48 dp, and no two are closer than 8 dp.
 *
 * The owner's audit measured the chips at 37.3 dp high. Material 3 asks for 48 x 48 dp with
 * 8 dp between targets. The test composes the real [PlayerScreen] and measures the semantics
 * nodes, so a custom chip height or a row with no vertical gap fails here rather than on a
 * phone. The emulator run, `scripts/smoke-android.mjs --a11y Player`, belongs to the frames
 * lane.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w360dp-h4000dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SleepChipsTouchTargetTest {

    @get:Rule
    val compose = createComposeRule()

    private val playing = NowPlaying(
        publicationId = "sea-room",
        title = "Sea Room",
        parts = listOf(
            PlaybackPart("The Shiants", PlaybackDuration.Known(300_000)),
            PlaybackPart("Bird Island", PlaybackDuration.Known(300_000)),
        ),
        partIndex = 0,
        offsetMillis = 42_000,
        session = PlaybackSession().started(),
        speed = PlaybackSpeed.of(1.0),
    )

    @Composable
    private fun Player(fontScale: Float) {
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
            StoryArcTheme {
                PlayerScreen(
                    playing = playing,
                    onToggle = {},
                    onSkip = {},
                    onSeek = {},
                    onSeekSettled = {},
                    onChooseChapter = {},
                    onSpeed = {},
                    // A running timer, so the Off chip is drawn too.
                    sleep = SleepTimer(SleepAfter.Duration(900_000), 754_000),
                    onSleep = {},
                    onBack = {},
                )
            }
        }
    }

    private val chips = listOf("Off", "5 min", "15 min", "30 min", "45 min", "60 min", "End of chapter")

    private fun anyChip() = chips.map(::hasText).reduce { a, b -> a or b }

    @Test
    fun `each sleep chip is a touch target of 48 dp`() {
        compose.setContent { Player(fontScale = 1f) }
        for (label in chips) {
            compose.onNodeWithText(label).performScrollTo().assertTouchTargetIsAtLeast()
        }
    }

    @Test
    fun `each sleep chip keeps 48 dp at the largest font size`() {
        compose.setContent { Player(fontScale = 2f) }
        for (label in chips) {
            compose.onNodeWithText(label).performScrollTo().assertTouchTargetIsAtLeast()
        }
    }

    @Test
    fun `no two sleep chips are closer than 8 dp, along a row or between rows`() {
        compose.setContent { Player(fontScale = 1f) }
        compose.onNodeWithText("Off").performScrollTo()

        compose.onAllNodes(anyChip()).assertTouchTargetsAreApart()
    }

    @Test
    fun `no two sleep chips are closer than 8 dp at the largest font size`() {
        compose.setContent { Player(fontScale = 2f) }
        compose.onNodeWithText("Off").performScrollTo()

        compose.onAllNodes(anyChip()).assertTouchTargetsAreApart()
    }
}
