package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Task 21.1: `AppContent` must reach the shelf through one movable pane, from both of its call
 * sites.
 *
 * `RotationKeepsThePaneTest` asserts that [rememberMovablePane] moves content. It cannot say
 * that `AppContent` uses it, and the shelf cannot be composed on the host: it needs a
 * `LibraryViewModel` and the app graph. So this reads the source, the way `EpubNextOfferWiringTest`
 * does. On the Pixel 6a emulator with six busy loops on four cores, a release build whose
 * shelf was a plain lambda held the main thread for 1.0 to 4.7 s in five of six first
 * rotations; with the movable pane the same rotation took 0.28 to 0.63 s.
 */
class RotationShelfWiringTest {

    @Test
    fun `the shelf is one movable pane`() {
        val panes = read(APP_PANES)
        assertTrue(
            "AppContent no longer builds the shelf with rememberMovablePane, so a rotation across" +
                " 840 dp composes the whole shelf again.",
            panes.contains("val shelf = rememberMovablePane {"),
        )
    }

    @Test
    fun `both call sites of the shelf call that one pane`() {
        val panes = read(APP_PANES)
        assertTrue(
            "The list pane of the split no longer calls the shelf pane.",
            panes.contains("listPane = { shelf() }"),
        )
        assertTrue(
            "The single column no longer calls the shelf pane.",
            Regex("""if \(navigation\.destination == AppDestination\.LIBRARY && screen == null\) \{[^}]*shelf\(\)""")
                .containsMatchIn(panes),
        )
        assertTrue(
            "AppContent draws the library destination from a second call site again.",
            Regex("""Destination\(host = host, destination = AppDestination\.LIBRARY\)""")
                .findAll(panes).count() == 1,
        )
    }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        if (!file.isFile) error("$path is not under ${androidRoot.absolutePath} — has it moved?")
        return file.readText()
    }

    private companion object {
        const val APP_PANES = "app/src/main/kotlin/app/storyarc/AppPanes.kt"

        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("No settings.gradle.kts above ${File("").absolutePath}.")
    }
}
