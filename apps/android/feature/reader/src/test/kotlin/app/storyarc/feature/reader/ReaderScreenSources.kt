package app.storyarc.feature.reader

import java.io.File

/**
 * The files the comic reader's screen is written across.
 *
 * `ReaderScreen.kt` held all of this until it passed the 800-line cap. The split moved code
 * between these files and changed none of it, so a source test that guards the screen reads
 * all of them. A guarded line that moves from one of them to another is then still found.
 */
internal val READER_SCREEN_FILES = listOf(
    "ReaderScreen.kt",
    "ReaderPager.kt",
    "ReaderPageSurface.kt",
    "ReaderPagerEffects.kt",
    "PdfTextLayers.kt",
    "ZoomablePage.kt",
    "EndOfPublication.kt",
)

/** The source of the screen, every file of it joined, from the module directory [module]. */
internal fun readerScreenSource(module: File): String =
    READER_SCREEN_FILES.joinToString("\n") { name ->
        val file = File(module, "src/main/kotlin/app/storyarc/feature/reader/$name")
        if (!file.isFile) error("$name is not under ${module.absolutePath} — has it moved?")
        file.readText()
    }
