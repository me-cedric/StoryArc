package app.storyarc.feature.epubreader

import app.storyarc.core.designsystem.theme.StoryArcWindowClass
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Where the theme surface earns the anchored presentation.
 *
 * `native-experience`, *Theme sheet on a large screen*: the popover arrives "on a tablet",
 * and [StoryArcWindowClass.MEDIUM] is Material's own name for the first class with one --
 * a portrait tablet or an unfolded foldable. D22 reads that scenario for Android.
 *
 * A plain JVM test over [showsAnchoredTheme] rather than a Compose one over [ThemeSurface]:
 * the branch opens a [ThemePopover] or a `ModalBottomSheet`, and both open a window of their
 * own that a Robolectric tree would have to animate into for no reason the boundary cares
 * about -- `ReadAloudRowTest` lifts past the same kind of window for the same reason.
 */
class ThemeSurfaceTest {

    @Test
    fun `compact stays the bottom sheet`() {
        assertFalse(StoryArcWindowClass.COMPACT.showsAnchoredTheme())
    }

    @Test
    fun `medium and wider earn the anchored popover`() {
        assertTrue(StoryArcWindowClass.MEDIUM.showsAnchoredTheme())
        assertTrue(StoryArcWindowClass.EXPANDED.showsAnchoredTheme())
        assertTrue(StoryArcWindowClass.LARGE.showsAnchoredTheme())
        assertTrue(StoryArcWindowClass.EXTRA_LARGE.showsAnchoredTheme())
    }
}
