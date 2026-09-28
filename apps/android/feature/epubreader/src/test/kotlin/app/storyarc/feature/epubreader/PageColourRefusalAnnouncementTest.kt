package app.storyarc.feature.epubreader

import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.ReaderPalette
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `native-experience`: Android drew the refusal as plain text with no live region, so a
 * refused pairing never reached TalkBack — the tapped swatch does not move and the reason
 * renders at the foot of the section, so a reader who cannot see the sheet heard nothing.
 * iOS posts an `AccessibilityNotification.Announcement` for the same case
 * (`PageColourSection.swift`).
 *
 * The window is sized tall enough to lay out every axis above the button: `PageColourSection`
 * is written for a scrolling sheet, and a default Robolectric window is short enough that a
 * bare `setContent` collapses the button below the fold to zero height, so a tap on it never
 * reaches the click at all.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w360dp-h2400dp")
class PageColourRefusalAnnouncementTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a refused pairing carries a polite live region`() {
        val pending = ReaderPalette(name = "Faint", background = "#FFFFFF", foreground = "#EEEEEE")

        compose.setContent {
            StoryArcTheme {
                PageColourSection(
                    inForce = null,
                    pending = pending,
                    onPreview = {},
                    onAdopt = { false },
                    onDiscard = {},
                )
            }
        }

        // "Use this colour" only draws while a pairing is pending, which the section is
        // handed directly here rather than through a swatch tap: no JVM test can lay out
        // a composable to find the swatch's own position, and the button is what carries
        // the refusal this test is over.
        compose.onNodeWithText("Use this colour").performClick()

        compose.onNode(
            SemanticsMatcher("carries a polite live region") { node ->
                node.config.getOrNull(SemanticsProperties.LiveRegion) == LiveRegionMode.Polite
            },
        ).assertExists()
    }
}
