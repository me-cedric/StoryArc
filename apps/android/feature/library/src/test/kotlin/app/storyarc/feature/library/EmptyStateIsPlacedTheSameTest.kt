package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That home and the library put the same empty state in the same place.
 *
 * Sharing the composable was supposed to stop the two drifting apart. It stopped the words and
 * the actions drifting and left the placement to each caller, so half the job was undone: home
 * drew it as a `LazyColumn` item, which lays out at the top, and the library drew it inside a
 * centred `Box`. On a OnePlus 7T Pro the two blocks sat 400 pixels apart, and a reader who
 * moved between the destinations saw the same sentence jump.
 *
 * Three claims, and each is a line a future edit could quietly remove.
 *
 * **Source text, and that is the second choice.** A Compose test can read a node's bounds, but
 * not through `fillParentMaxSize`: that modifier only means anything inside a lazy layout, and
 * composing a `LazyColumn` under Robolectric to measure one item's centre is more machinery
 * than the defect. `NoSegmentedButtonsTest` beside this one reads source for the same reason.
 * It is a tripwire, not a proof: the frames under
 * `docs/designs/screenshots/android-empty-state-2026-09-08/` are the measurement.
 */
class EmptyStateIsPlacedTheSameTest {

    private val root = File("src/main/kotlin/app/storyarc/feature/library")

    private fun source(name: String): String {
        val file = File(root, name)
        assertTrue("${file.path} could not be read — has it moved?", file.isFile)
        return file.readText()
    }

    @Test
    fun `the empty state centres itself on both axes`() {
        val states = source("LibraryStates.kt")

        assertTrue(
            "the block no longer centres vertically, so a caller decides where it sits",
            states.contains("Arrangement.spacedBy(StoryArcSpace.md, Alignment.CenterVertically)"),
        )
        assertTrue(
            "the block no longer centres horizontally, so it will not match iOS",
            states.contains("horizontalAlignment = Alignment.CenterHorizontally"),
        )
    }

    @Test
    fun `home gives it the whole viewport rather than one item's height`() {
        val home = source("HomeScreen.kt")

        // `fillMaxSize` inside a lazy item measures against unbounded height and collapses,
        // which is exactly how the block ended up at the top.
        assertTrue(
            "home no longer hands the empty state the viewport height",
            home.contains("modifier = Modifier.fillParentMaxSize()"),
        )
    }

    @Test
    fun `home keeps its shelf padding off the empty state`() {
        val home = source("HomeScreen.kt")

        // The extra inset under the last shelf moves a centred block's middle up by half of
        // it. Measured: the title sat 55 pixels above the library's.
        assertTrue(
            "the shelf's bottom inset is applied to the empty state again",
            home.contains("if (surface.isBare) 0.dp else StoryArcSpace.xxl"),
        )
    }

    @Test
    fun `both destinations draw one composable and not two`() {
        val calls = listOf("HomeScreen.kt", "LibraryScreen.kt")
            .count { source(it).contains("EmptyLibrary(") }

        assertEquals("home and the library must both draw EmptyLibrary", 2, calls)
    }
}
