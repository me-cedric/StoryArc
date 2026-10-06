package app.storyarc.feature.library

import app.storyarc.core.format.CoverOverrideStore
import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaSeries
import java.util.UUID
import kotlin.io.path.createTempDirectory
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * A reading-list entry draws the cover the reader chose for that chapter.
 *
 * The publication page and the list name one chapter in two places. The list must name it
 * exactly as `KavitaContributor` does, or the store files the choice under one key and the
 * list asks under another -- and the list quietly goes on drawing the server's cover.
 */
class KavitaListEntryCoverTest {

    private val source = UUID.fromString("55555555-5555-5555-5555-555555555555")
    private val series = KavitaSeries(id = 3, name = "Tidal Reach")
    private val chapter = KavitaChapter(id = 41)

    @Test
    fun `a chapter's chosen cover is drawn in the list, and the server is not asked`() = runTest {
        val overrides = CoverOverrideStore(createTempDirectory("overrides").toFile())
        val onThePage = KavitaContributor.publication(source, series, chapter)
        overrides.store(byteArrayOf(7, 7), onThePage)
        var asked = false

        val drawn = chapterCover(overrides, source.toString(), chapter.id) {
            asked = true
            byteArrayOf(1)
        }

        assertEquals(listOf<Byte>(7, 7), drawn.toList())
        assertEquals(false, asked)
    }

    @Test
    fun `a chapter with no chosen cover draws the server's`() = runTest {
        val overrides = CoverOverrideStore(createTempDirectory("overrides").toFile())

        val drawn = chapterCover(overrides, source.toString(), chapter.id) { byteArrayOf(1) }

        assertEquals(listOf<Byte>(1), drawn.toList())
    }
}
