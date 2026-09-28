package app.storyarc.feature.library

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The continuation loop itself: which pages it asks for, which answers it folds in, and
 * where it stops.
 *
 * `sources`' *More from a source than the library holds*: "stop and resume cleanly when the
 * source becomes unreachable". [readOnward] is the loop `continueReadingKavita` runs, with
 * the server and the view model replaced by a page table and one progress value. iOS's
 * `KavitaContinuedReadTests` asks the same four questions.
 */
class KavitaContinuedReadTest {

    private fun page(series: Int, holdsMore: Boolean) =
        KavitaContributor.Page(SourceSlice(emptyList(), holdsMore), seriesRead = series)

    /** One source's progress, and a record of every page the loop folded in. */
    private class Reader(var progress: SourceReadProgress?) {
        val landed = mutableListOf<SourceReadStep>()

        fun land(step: SourceReadStep) {
            landed += step
            progress = (step as? SourceReadStep.Continuing)?.progress
        }
    }

    @Test
    fun `a read goes on page by page until a short page ends it`() = runTest {
        val reader = Reader(SourceReadProgress(read = 60, total = 154, nextPage = 2))
        val asked = mutableListOf<Int>()
        val pages = mapOf(2 to page(60, holdsMore = true), 3 to page(34, holdsMore = false))

        readOnward({ reader.progress }, { asked += it; pages[it] }, { _, step -> reader.land(step) })

        assertEquals(listOf(2, 3), asked)
        assertEquals(
            listOf(
                SourceReadStep.Continuing(SourceReadProgress(read = 120, total = 154, nextPage = 3)),
                SourceReadStep.Finished(SourceReadProgress(read = 154, total = 154, nextPage = 4)),
            ),
            reader.landed,
        )
        assertNull(reader.progress)
    }

    @Test
    fun `a refused page leaves the read where it stood`() = runTest {
        val reader = Reader(SourceReadProgress(read = 60, total = 215, nextPage = 2))
        val pages = mapOf(2 to page(60, holdsMore = true))

        readOnward({ reader.progress }, { pages[it] }, { _, step -> reader.land(step) })

        assertEquals(SourceReadProgress(read = 120, total = 215, nextPage = 3), reader.progress)
    }

    @Test
    fun `an answer for a page another reader already folded in is dropped`() = runTest {
        // A pull-to-refresh starts a second reader while the first is waiting on page two.
        // The first one lands page two while the second is still waiting on it.
        val reader = Reader(SourceReadProgress(read = 60, total = 215, nextPage = 2))
        val alreadyFolded = SourceReadProgress(read = 120, total = 215, nextPage = 3)

        readOnward(
            progress = { reader.progress },
            fetch = { requested ->
                if (requested == 2) reader.progress = alreadyFolded
                page(60, holdsMore = true).takeIf { requested == 2 }
            },
            land = { _, step -> reader.land(step) },
        )

        assertEquals(emptyList<SourceReadStep>(), reader.landed)
        assertEquals(alreadyFolded, reader.progress)
    }

    @Test
    fun `a read another reader finished is not opened again`() = runTest {
        val reader = Reader(SourceReadProgress(read = 120, total = 154, nextPage = 3))

        readOnward(
            progress = { reader.progress },
            fetch = { requested ->
                reader.progress = null
                page(60, holdsMore = true).takeIf { requested == 3 }
            },
            land = { _, step -> reader.land(step) },
        )

        assertEquals(emptyList<SourceReadStep>(), reader.landed)
        assertNull(reader.progress)
    }
}
