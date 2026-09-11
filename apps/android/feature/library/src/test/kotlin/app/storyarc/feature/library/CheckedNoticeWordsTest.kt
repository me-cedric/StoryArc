package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * What the checked line says in the first minute, which is when it is read.
 *
 * **It said "Libraries checked 0 minutes ago."** on an emulator on 2026-09-11, in the
 * moment right after a refresh -- which is the moment a reader is most likely to be looking,
 * because they had just asked for one. `DateUtils.getRelativeTimeSpanString` was given
 * `MINUTE_IN_MILLIS` as its minimum resolution, and that resolution reads every duration
 * under a minute as zero of them.
 *
 * iOS says "5 seconds ago" for the same instant, from
 * `.formatted(.relative(presentation: .named))`. ADR-0001 asks a twin for the same words
 * about the same state, so this asserts the words rather than the constant: a test that
 * checked which constant is passed would pass for the wrong reason the day the platform
 * changes what the constant means.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CheckedNoticeWordsTest {

    @get:Rule
    val compose = createComposeRule()

    private fun drawCheckedAgo(millisAgo: Long) {
        compose.setContent {
            StoryArcTheme {
                CheckedNotice(checkedAtEpochMillis = System.currentTimeMillis() - millisAgo)
            }
        }
    }

    @Test
    fun `the first seconds are just now, not zero of anything`() {
        drawCheckedAgo(millisAgo = 900)
        compose.onNodeWithText("just now", substring = true).assertExists()
        compose.onNodeWithText("0 ", substring = true).assertDoesNotExist()
    }

    @Test
    fun `seconds ago is counted in seconds, not in zero minutes`() {
        drawCheckedAgo(millisAgo = 20_000)
        compose.onNodeWithText("0 minutes", substring = true).assertDoesNotExist()
        compose.onNodeWithText("second", substring = true).assertExists()
    }

    @Test
    fun `a minute ago is still counted in minutes`() {
        // The coarser wording is right once there is a whole minute to name, so the fix must
        // not have pushed everything into seconds.
        drawCheckedAgo(millisAgo = 5 * 60_000)
        compose.onNodeWithText("minute", substring = true).assertExists()
    }
}
