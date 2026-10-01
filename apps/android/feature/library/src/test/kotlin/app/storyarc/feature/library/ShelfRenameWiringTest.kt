package app.storyarc.feature.library

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `collections-and-reading-lists` task 7.10: the menu item and the dialog it opens, the one
 * half of this task `ShelfRenamingTest` and `ShelvesTest` cannot reach — `ShelfCreationTest`'s
 * own reason: an `OutlinedTextField` inside an `AlertDialog` never settles under Robolectric.
 */
class ShelfRenameWiringTest {

    private fun read(path: String): String {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, path)
        if (!file.isFile) error("$path is not under ${module.absolutePath} — has it moved?")
        return file.readText()
    }

    @Test
    fun `the shelf card offers rename beside delete`() {
        val cover = read(SHELF_COVER)
        assertTrue(
            "ShelfCard no longer has an onRename parameter, so nothing can open the dialog.",
            cover.contains("onRename: (() -> Unit)? = null"),
        )
        assertTrue(
            "ShelfCard's menu no longer draws a Rename item for a caller that passed onRename.",
            cover.contains("if (onRename != null) {"),
        )
    }

    @Test
    fun `local collections and local lists offer rename, by the model's own call`() {
        val screen = read(SHELVES_SCREEN)
        assertTrue(
            "A local collection's card no longer passes onRename, so its menu has no Rename.",
            screen.contains("onRename = { renaming = ShelfRenameTarget(isList = false, collection.id, collection.name) }"),
        )
        assertTrue(
            "A local reading list's card no longer passes onRename, so its menu has no Rename.",
            screen.contains("onRename = { renaming = ShelfRenameTarget(isList = true, list.id, list.name) }"),
        )
        assertTrue(
            "Confirming a rename no longer calls viewModel.renameList.",
            screen.contains("viewModel.renameList(target.id, target.name)"),
        )
        assertTrue(
            "Confirming a rename no longer calls viewModel.renameCollection.",
            screen.contains("viewModel.renameCollection(target.id, target.name)"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val SHELF_COVER = "src/main/kotlin/app/storyarc/feature/library/ShelfCover.kt"
        const val SHELVES_SCREEN = "src/main/kotlin/app/storyarc/feature/library/ShelvesScreen.kt"
    }
}
