package app.storyarc.feature.library

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The continuation loop a network share and an OPDS catalogue share, with the cursor a
 * folder-queue list rather than a page number -- [readSourceOnward] is a page table and one
 * progress value standing in for either source. `KavitaContinuedReadTest` asks the same four
 * questions of `readOnward`.
 */
class ContinuedReadLoopTest {

    private fun slice(found: Int, holdsMore: Boolean) = SourceSlice((0 until found).map { fakePublication() }, holdsMore)

    private fun fakePublication() = app.storyarc.core.model.Publication(
        identity = app.storyarc.core.model.PublicationIdentity(normalizedPath = "x"),
        format = app.storyarc.core.model.PublicationFormat.CBZ,
        displayTitle = "x",
        origin = app.storyarc.core.model.MetadataOrigin.INFERRED,
    )

    /** One source's progress and cursor, and a record of every page the loop folded in. */
    private class Reader(var progress: SourceReadProgress?, var cursor: Int) {
        val landed = mutableListOf<SourceReadStep>()

        fun land(step: SourceReadStep) {
            landed += step
            progress = (step as? SourceReadStep.Continuing)?.progress
        }
    }

    @Test
    fun `a read goes on cursor by cursor until a short page ends it`() = runTest {
        val reader = Reader(SourceReadProgress(read = 60, total = null, nextPage = 2), cursor = 1)
        val asked = mutableListOf<Int>()
        val pages = mapOf(1 to (slice(60, holdsMore = true) to 2), 2 to (slice(34, holdsMore = false) to 3))

        readSourceOnward(
            progress = { reader.progress },
            cursor = { reader.cursor },
            fetch = { asked += it; pages[it] },
            advance = { reader.cursor = it },
            land = { _, step -> reader.land(step) },
        )

        assertEquals(listOf(1, 2), asked)
        assertEquals(
            listOf(
                SourceReadStep.Continuing(SourceReadProgress(read = 120, total = null, nextPage = 3)),
                SourceReadStep.Finished(SourceReadProgress(read = 154, total = null, nextPage = 4)),
            ),
            reader.landed,
        )
        assertNull(reader.progress)
    }

    @Test
    fun `a refused page leaves the read where it stood`() = runTest {
        val reader = Reader(SourceReadProgress(read = 60, total = null, nextPage = 2), cursor = 1)
        val pages = mapOf(1 to (slice(60, holdsMore = true) to 2))

        readSourceOnward(
            progress = { reader.progress },
            cursor = { reader.cursor },
            fetch = { pages[it] },
            advance = { reader.cursor = it },
            land = { _, step -> reader.land(step) },
        )

        assertEquals(SourceReadProgress(read = 120, total = null, nextPage = 3), reader.progress)
    }

    @Test
    fun `an answer for a page another reader already folded in is dropped`() = runTest {
        // A pull-to-refresh starts a second reader while the first is waiting on round two.
        val reader = Reader(SourceReadProgress(read = 60, total = null, nextPage = 2), cursor = 1)
        val alreadyFolded = SourceReadProgress(read = 120, total = null, nextPage = 3)

        readSourceOnward(
            progress = { reader.progress },
            cursor = { reader.cursor },
            fetch = { cursor ->
                reader.progress = alreadyFolded
                (slice(60, holdsMore = true) to 2).takeIf { cursor == 1 }
            },
            advance = { reader.cursor = it },
            land = { _, step -> reader.land(step) },
        )

        assertEquals(emptyList<SourceReadStep>(), reader.landed)
        assertEquals(alreadyFolded, reader.progress)
    }

    @Test
    fun `a read another reader finished is not opened again`() = runTest {
        val reader = Reader(SourceReadProgress(read = 120, total = null, nextPage = 3), cursor = 2)

        readSourceOnward(
            progress = { reader.progress },
            cursor = { reader.cursor },
            fetch = { cursor ->
                reader.progress = null
                (slice(60, holdsMore = true) to 3).takeIf { cursor == 2 }
            },
            advance = { reader.cursor = it },
            land = { _, step -> reader.land(step) },
        )

        assertEquals(emptyList<SourceReadStep>(), reader.landed)
        assertNull(reader.progress)
    }
}
