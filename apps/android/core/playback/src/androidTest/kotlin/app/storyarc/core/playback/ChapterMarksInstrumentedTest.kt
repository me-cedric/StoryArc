package app.storyarc.core.playback

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * That a chaptered container names its chapters before anything plays it.
 *
 * **Instrumented because a host JVM cannot answer this.** [ChapterMarks.parts] prepares a
 * media source and reads its track formats, and the MP4 extractor that finds the chapter
 * track is the platform's. `AudiobookChaptersTest` asserts every rule that turns marks into
 * parts, against marks of our own shape; what it cannot say is that a real M4B produces any.
 *
 * The fixtures are the corpus's own, mounted as assets of this suite the way `:core:format`
 * mounts them. `packages/test-fixtures/scripts/generate.py` writes `chaptered.m4b` with three
 * chapters — `One` at 0s, `Two` at 2s, `Three` at 4s, over six seconds of audio — and the
 * corpus manifest states the same three. So the expectations here come from the generator and
 * not from this reader. `scripts/corpus.mjs` copies the same bytes onto a device as
 * `Sea Room.m4b`, which is the file the manual walk opens.
 */
@RunWith(AndroidJUnit4::class)
class ChapterMarksInstrumentedTest {

    @Test
    fun aChapteredM4bNamesItsThreeChaptersWithNoPlayerAndNoAudio() = runBlocking {
        val parts = partsOf("audiobooks/chaptered.m4b")

        assertEquals(
            "An M4B keeps its chapter marks in the container. Nothing else names them, so a" +
                " page that could not read them listed one part until the book played.",
            listOf("One", "Two", "Three"),
            parts.map { it.title },
        )
    }

    @Test
    fun everyChapterStatesTheLengthTheContainerGivesIt() = runBlocking {
        // Two seconds each. The first two come from the next mark's start; the last comes
        // from the file's own duration, which the same retrieval reports.
        assertEquals(
            listOf(2_000L, 2_000L, 2_000L),
            partsOf("audiobooks/chaptered.m4b").map { it.duration.statedMillis },
        )
    }

    @Test
    fun anUnchapteredFileIsOnePartNamedForThePublication() = runBlocking {
        // `publication-formats`: an unchaptered audiobook is a normal audiobook. It reports
        // its own length, because the retrieval measured it.
        val parts = partsOf("audiobooks/unchaptered.m4a")

        assertEquals(listOf("Sea Room"), parts.map { it.title })
        assertEquals(5_000L, parts.single().duration.statedMillis)
    }

    @Test
    fun aFileThisDeviceCannotOpenIsStillOnePartAndNotAnEmptyList() = runBlocking {
        val missing = Uri.fromFile(File(context.cacheDir, "no-such-book.m4b")).toString()
        val parts = ChapterMarks.parts(context, missing, "Sea Room", "Chapter")

        assertEquals(listOf("Sea Room"), parts.map { it.title })
        assertEquals(PlaybackDuration.Unknown, parts.single().duration)
    }

    private val context get() = InstrumentationRegistry.getInstrumentation().context

    private suspend fun partsOf(name: String): List<PlaybackPart> =
        ChapterMarks.parts(context, fixtureUri(name), "Sea Room", "Chapter")

    private fun fixtureUri(name: String): String {
        val target = File(context.cacheDir, name.substringAfterLast('/'))
        if (!target.exists()) {
            context.assets.open(name).use { input -> target.outputStream().use(input::copyTo) }
        }
        return Uri.fromFile(target).toString()
    }
}
