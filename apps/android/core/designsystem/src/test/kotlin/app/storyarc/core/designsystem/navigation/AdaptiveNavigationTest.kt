package app.storyarc.core.designsystem.navigation

import androidx.compose.material3.NavigationItemIconPosition
import androidx.compose.material3.ShortNavigationBarArrangement
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * How the navigation bar lays its items out, per width class.
 *
 * Material: *"Use vertical items in compact windows … horizontal items in medium windows"*,
 * and for the medium bar it pairs that with a centered arrangement rather than one that
 * spreads four items across a window wide enough to make the gaps look accidental.
 *
 * `NavigationSuiteScaffold` applies both for itself. [AdaptiveNavigationShell] does not use
 * it — it uses [NavigationSuiteScaffoldLayout] and composes its own `ShortNavigationBarItem`s,
 * which is what lets one list of [NavigationEntry] build the bar, the collapsed rail and the
 * expanded rail. The cost of that is exactly this: the layout inherits nothing about its
 * items, so a guideline the suite would have honoured for free has to be honoured by hand.
 * It was not, until this test.
 *
 * Asserted through two properties rather than by composing a bar, for the reason
 * [NavigationLabelTest] gives about [pinsLabelFontScale]: the rule is a function of the
 * width class alone, so it is decidable on a plain JVM in milliseconds rather than in an
 * instrumented test nobody runs.
 *
 * **A property test cannot see whether the value is passed**, and that is the mutation that
 * matters: delete both arguments from the call site and every assertion above stays green
 * while the bar goes back to being wrong. The last two cases read the module's own source
 * for exactly that, in the manner of `ReaderChromeWiringTest`.
 *
 * Both APIs are public and stable on material3 1.5.0-alpha26; `javap` over `material3.aar`
 * shows `NavigationItemIconPosition$Companion.getStart` and
 * `ShortNavigationBarArrangement$Companion.getCentered`, and shows that `ShortNavigationBar`
 * takes an arrangement and **no `shape`** — which is why the Android bar is edge-to-edge and
 * iOS's is a floating capsule.
 */
class AdaptiveNavigationTest {

    @Test
    fun `a medium window lays its navigation items out horizontally`() {
        assertEquals(
            NavigationItemIconPosition.Start,
            NavigationSuiteType.ShortNavigationBarMedium.barIconPosition,
        )
    }

    @Test
    fun `a medium window centres its navigation items rather than spreading them`() {
        assertEquals(
            ShortNavigationBarArrangement.Centered,
            NavigationSuiteType.ShortNavigationBarMedium.barArrangement,
        )
    }

    @Test
    fun `a compact window keeps the icon above the label`() {
        // The other half of the same sentence, and the half that was already right. Without
        // it the test above is satisfied by making every width horizontal, which would put
        // four horizontal items across a 360 dp phone.
        assertEquals(
            NavigationItemIconPosition.Top,
            NavigationSuiteType.ShortNavigationBarCompact.barIconPosition,
        )
    }

    @Test
    fun `a compact window gives each destination an equal share of the width`() {
        assertEquals(
            ShortNavigationBarArrangement.EqualWeight,
            NavigationSuiteType.ShortNavigationBarCompact.barArrangement,
        )
    }

    @Test
    fun `the rails answer as the compact bar does, because neither draws a bar`() {
        // Not a claim about rails — they are drawn by `WideNavigationRailItem`, which reads
        // neither property. It is a claim that the `when` is exhaustive and total, so a
        // width class added by a future alpha cannot land on an uninitialised branch.
        listOf(
            NavigationSuiteType.WideNavigationRailCollapsed,
            NavigationSuiteType.WideNavigationRailExpanded,
            NavigationSuiteType.None,
        ).forEach { type ->
            assertEquals(type.toString(), NavigationItemIconPosition.Top, type.barIconPosition)
            assertEquals(
                type.toString(),
                ShortNavigationBarArrangement.EqualWeight,
                type.barArrangement,
            )
        }
    }

    /**
     * This module's own source, at the path its build script hands to the test JVM.
     *
     * Deliberately not discovered. Walking up from the working directory leaves the module:
     * this repository nests agent worktrees at `.claude/worktrees/<name>/`, so the walk
     * climbs out of the worktree under test and reads the parent checkout's copy — a guard
     * passing or failing on source that was never built. [MODULE_DIRECTORY] is set from
     * `projectDir` in `build.gradle.kts`, which is the module being built by construction,
     * and the file is declared an input of the test task there.
     *
     * Missing is a failure rather than a skip: a guard that cannot find what it guards has
     * to say so, or it passes forever after the file is renamed.
     */
    private val source: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and" +
                    " will not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :core:designsystem:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, SHELL_SOURCE)
        if (!file.isFile) {
            error("$SHELL_SOURCE is not under ${module.absolutePath} — has it moved?")
        }
        file.readText()
    }

    @Test
    fun `the bar passes its arrangement and its items their icon position`() {
        assertTrue(
            "ShortNavigationBar no longer takes the width class's arrangement.",
            source.contains("ShortNavigationBar(arrangement = type.barArrangement)"),
        )
        assertTrue(
            "ShortNavigationBarItem no longer takes the width class's icon position.",
            source.contains("iconPosition = type.barIconPosition"),
        )
    }

    @Test
    fun `the bar states no shape of its own`() {
        // Not a style rule — a structural one. `ShortNavigationBar` exposes no `shape`
        // parameter at all on material3 1.5.0-alpha26, verified with `javap` over
        // `material3.aar`, and Material states twice that the container spans the full
        // window width. So the Android bar is edge-to-edge with no capsule, no inset and no
        // rounding while iOS's floats, and that divergence is deliberate. This fails if
        // somebody reaches for a `Surface` or a `clip` to port the iOS capsule across.
        assertFalse(
            "The navigation bar has grown a shape. Android's bar is edge-to-edge; the" +
                " floating capsule is iOS's answer and does not port.",
            source.contains("ShortNavigationBar(shape") || source.contains("shape = "),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.designsystem.projectDir"
        const val SHELL_SOURCE =
            "src/main/kotlin/app/storyarc/core/designsystem/navigation/AdaptiveNavigation.kt"
    }
}
