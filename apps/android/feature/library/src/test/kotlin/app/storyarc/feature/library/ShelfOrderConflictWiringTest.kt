package app.storyarc.feature.library

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `collections-and-reading-lists` task 7.4: the screen's own glue around
 * `KavitaSync.reorder` — captured in [ShelfOrderConflictTest] and [ShelfOrderTest] as plain
 * behaviour, but the glue itself is a drag handler a behavioural test cannot reach without
 * driving a real drag gesture through a rendered list.
 */
class ShelfOrderConflictWiringTest {

    @Test
    fun `the screen reads a baseline once, and passes it to every drag`() {
        val screens = read(KAVITA_SHELF_SCREENS)
        assertTrue(
            "KavitaListScreen no longer captures the server's order when it opens, so a" +
                " drag has no baseline to check a later send against.",
            screens.contains("baseline = items.map { it.chapterId }"),
        )
        assertTrue(
            "A drag no longer passes the captured baseline to KavitaSync.reorder, so" +
                " every send goes through unchecked again.",
            screens.contains("baseline = baseline,"),
        )
    }

    @Test
    fun `a dropped order writes the same conflict notice an append conflict does`() {
        val screens = read(KAVITA_SHELF_SCREENS)
        assertTrue(
            "A dropped order no longer writes a ShelfConflictNotice, so the reader is" +
                " never told their order did not take.",
            screens.contains("ShelfConflictNotice("),
        )
        assertTrue(
            "The notice no longer marks itself as an order conflict, so the shelves" +
                " screen would draw the append wording -- \"these were not added\" -- over" +
                " an order that named nothing.",
            screens.contains("isOrder = true,"),
        )
    }

    @Test
    fun `the shelves screen draws the order conflict's own sentence`() {
        val shelves = read(SHELVES_SCREEN)
        assertTrue(
            "ShelvesScreen no longer branches on isOrder, so an order conflict is drawn" +
                " with the append wording, which names entries an order conflict has none" +
                " of.",
            shelves.contains("if (notice.isOrder) {"),
        )
        assertTrue(
            "The order branch no longer reads shelves_conflict_body_order, so it falls" +
                " back to whatever the append string happens to be.",
            shelves.contains("R.string.shelves_conflict_body_order"),
        )
    }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        if (!file.isFile) error("$path is not under ${androidRoot.absolutePath} — has it moved?")
        return file.readText()
    }

    private companion object {
        const val KAVITA_SHELF_SCREENS =
            "feature/library/src/main/kotlin/app/storyarc/feature/library/KavitaShelfScreens.kt"
        const val SHELVES_SCREEN =
            "feature/library/src/main/kotlin/app/storyarc/feature/library/ShelvesScreen.kt"

        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
