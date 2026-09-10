package app.storyarc.core.designsystem.navigation

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The shell consumes the navigation bar's window inset, and consumes it exactly once.
 *
 * `NavigationSuiteScaffoldLayout` -- the bare layout this shell calls -- reserves the bar's
 * *height* and does not consume its *inset*. The modifier that consumes it,
 * `navigationSuiteScaffoldConsumeWindowInsets`, lives in `NavigationSuiteScaffold`, the
 * wrapper this shell deliberately does not use. So without a `consumeWindowInsets` here,
 * every hosted screen's own `Scaffold` reports the gesture inset again and pays it a second
 * time: 24 dp of dead background between the last row and the bar, measured on the phone at
 * `docs/designs/screenshots/server-shelves-2026-09-10/`.
 *
 * A source guard rather than a composition test, and that is a real limit worth stating:
 * Robolectric's window reports no system-bar inset, so a test that composed the shell and
 * read a child's padding would pass whether or not the inset was consumed. What proves the
 * behaviour is the device frame; what this stops is the line being deleted by someone who
 * reads the height reservation and concludes the inset is handled too -- which is the
 * mistake the comment at the navigation slot used to make.
 */
class NavigationInsetIsConsumedOnceTest {

    private val shell = File(
        "src/main/kotlin/app/storyarc/core/designsystem/navigation/AdaptiveNavigation.kt",
    ).readText()

    @Test
    fun `the content slot consumes the system bars inset`() {
        assertTrue(
            "AdaptiveNavigation.kt no longer consumes the navigation inset. Nothing else does, " +
                "so every screen's Scaffold will pay it twice and every list will end short.",
            shell.contains("consumeWindowInsets(") && shell.contains("WindowInsets.systemBars.only("),
        )
    }

    @Test
    fun `it consumes the side the layout actually took`() {
        // A bar takes the bottom and a rail takes the start edge. Consuming the wrong one
        // leaves the dead band on one layout and eats real content on the other.
        assertTrue(
            "The consumed side must follow the layout: Bottom under a bar, Start beside a rail.",
            shell.contains("WindowInsetsSides.Start") && shell.contains("WindowInsetsSides.Bottom"),
        )
    }

    @Test
    fun `it consumes nothing when there is no navigation to pay for`() {
        assertTrue(
            "With no navigation control there is no reserved room, so consuming would take " +
                "space the reader's content is entitled to.",
            shell.contains("if (!showsNavigation)"),
        )
    }
}
