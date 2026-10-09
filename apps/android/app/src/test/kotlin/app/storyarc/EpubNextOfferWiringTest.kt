package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `collections-and-reading-lists` task 7.2: the reflowable EPUB reader offers what comes
 * next at the end, the way the paged reader's own end screen already does. The EPUB reader
 * is a separate activity with no library of its own, so the offer and the reopening of the
 * choice are split across two files the way a behavioural test cannot reach — see
 * `AudioSurfacesAreWiredTest` for the same shape on the audiobook side of this task.
 */
class EpubNextOfferWiringTest {

    @Test
    fun `the next entry is resolved and offered before the EPUB reader opens`() {
        val shell = read(APP_SHELL)
        assertTrue(
            "AppShell no longer asks offeredNext what comes after this publication, so" +
                " the EPUB reader is never told what to offer at its end.",
            shell.contains("val next = library.offeredNext(publication).also { epubNext.value = it }"),
        )
        assertTrue(
            "AppShell no longer puts the offer on the EPUB reader's intent, so the end" +
                " screen has nothing to name.",
            shell.contains(").offeringNext(next)"),
        )
        assertTrue(
            "AppShell no longer launches the EPUB reader through the result launcher, so" +
                " a choice made on its end screen has nowhere to report back to.",
            shell.contains("epubLauncher.value?.launch(intent)"),
        )
    }

    @Test
    fun `the reader's choice reopens through the library, not inside the activity`() {
        val shell = read(APP_SHELL)
        assertTrue(
            "AppShell no longer reads EXTRA_RESULT_NEXT_ID from the activity result, so" +
                " the end screen's choice is never read back.",
            shell.contains("result.data?.getStringExtra(EXTRA_RESULT_NEXT_ID)"),
        )
        assertTrue(
            "The offered entry is no longer opened through openEntry, so tapping the offer" +
                " for a server list's next entry, which has no file yet, does nothing.",
            shell.contains("epubNext.value?.takeIf { it.id == nextId }?.let(host::openEntry)"),
        )
    }

    @Test
    fun `the activity asks for the offer and hands a chosen next back as a result`() {
        val activity = read(EPUB_READER_ACTIVITY) + read(EPUB_READER_CONTENT)
        assertTrue(
            "EpubReaderActivity no longer asks EpubEndOfBookOffer to draw, so a reader" +
                " who reaches the end of the book sees no offer.",
            activity.contains("EpubEndOfBookOffer(this@EpubReaderContent, failure, progression)"),
        )
        assertTrue(
            "Choosing the offer no longer sets a result the launcher can read, so the" +
                " choice is lost the moment this activity finishes.",
            read(EPUB_END_OF_PUBLICATION).contains("Intent().putExtra(EXTRA_RESULT_NEXT_ID, nextId)"),
        )
    }

    @Test
    fun `the offer draws only at the end, and only when there is one to draw`() {
        val offer = read(EPUB_END_OF_PUBLICATION)
        assertTrue(
            "EpubEndOfBookOffer no longer reads the next id out of the intent, so the" +
                " offer never knows what to name or open.",
            offer.contains("""activity.intent.getStringExtra(EXTRA_NEXT_ID) ?: return"""),
        )
        assertTrue(
            "The offer is no longer gated on reaching the end of the book, so it would" +
                " draw over every page rather than only the last one.",
            offer.contains("!endOfBookReached(atLastPage, progression)"),
        )
    }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        if (!file.isFile) error("$path is not under ${androidRoot.absolutePath} — has it moved?")
        return file.readText()
    }

    private companion object {
        const val APP_SHELL = "app/src/main/kotlin/app/storyarc/AppShell.kt"
        const val EPUB_READER_ACTIVITY =
            "feature/epubreader/src/main/kotlin/app/storyarc/feature/epubreader/EpubReaderActivity.kt"
        const val EPUB_READER_CONTENT =
            "feature/epubreader/src/main/kotlin/app/storyarc/feature/epubreader/EpubReaderContent.kt"
        const val EPUB_END_OF_PUBLICATION =
            "feature/epubreader/src/main/kotlin/app/storyarc/feature/epubreader/EpubEndOfPublication.kt"

        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
