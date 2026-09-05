package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Home with every source down, and Home while a slow one is still answering.
 *
 * The design direction cites this as Plex's documented failure: watched state syncs across
 * servers but the Continue Watching row does not, so home becomes a union of libraries and
 * a *fragment* of the reader's own history. `home-screen` answers it with a requirement —
 * the surface renders "complete and immediately, with the same shelves in the same order as
 * when the sources are up" — and adds that no shelf "appears, reorders or grows once" a
 * source answers.
 *
 * **Both are promises about something *not* happening, which is the kind that rots
 * quietly.** Until 2026-09-05 the first was asserted on iOS only, by
 * `HomeOfflineTests.shelvesDoNotDependOnASource`, and this file is its mirror.
 * `HomeShelvesTest`'s two reachability cases assert the *per-entry* flag and never the
 * surface up against the surface down, which is a different claim.
 *
 * **The second was asserted nowhere, on either platform.** It was argued in
 * `HomeShelves`' own KDoc and by the shape of the `remember` in `HomeDestination` — which
 * is exactly the kind of proof a test replaces. It is asserted here by the only honest
 * means a pure surface allows: assembling the same library at three points along a source
 * coming back, and comparing the results element by element. If a source's state could
 * reach a shelf, one of the three would differ.
 */
class HomeOfflineTest {

    private companion object {
        const val NOW = 1_700_000_000_000L
    }

    /**
     * A library of three issues, one part-read and one finished — the same fixture iOS's
     * `HomeOfflineTests` builds, so the two platforms are answering one question.
     */
    private val first = issue("Saga", "1")
    private val second = issue("Saga", "2")
    private val third = issue("Saga", "3")
    private val library = listOf(first, second, third)
    private val progress = mapOf(
        first.id to finished(NOW - 1_000),
        second.id to partRead(NOW - 500),
    )

    private fun surface(readable: (Publication) -> Boolean) = HomeShelves.assemble(
        publications = library,
        progress = { progress[it.id] },
        isReadableNow = readable,
        nowEpochMillis = NOW,
    )

    /** Everything the surface holds, flattened, so a comparison cannot miss a shelf. */
    private fun shape(surface: HomeSurface): List<String> =
        surface.keepReading.map { "keep:${it.id}" } +
            surface.upNext.map { "next:${it.id}" } +
            surface.recentlyAdded.map { "recent:${it.id}" } +
            surface.finished.flatMap { group -> group.entries.map { "done:${group.period}:${it.id}" } }

    @Test
    fun `the same shelves, in the same order, with every source unreachable`() {
        val up = surface { true }
        val down = surface { false }

        assertEquals(shape(up), shape(down))
    }

    @Test
    fun `keep reading is not empty when nothing can be reached`() {
        assertEquals(1, surface { false }.keepReading.size)
    }

    @Test
    fun `a publication the app cannot open stays on the shelf and is marked, not dropped`() {
        // The bytes go away -- the share unmounts, the card is pulled -- and the row keeps
        // its length. That is the whole rule: dimmed, never dropped.
        val entry = surface { false }.keepReading.single()

        assertEquals(second.id, entry.id)
        assertFalse(entry.isReadableNow)
    }

    @Test
    fun `no shelf appears, reorders or grows when a slow source answers`() {
        // Three points along one source coming back: nothing reachable, the source answering
        // for some publications, everything reachable. `home-screen` requires the surface to
        // be identical at all three -- reachability decides a *dim*, never a membership and
        // never an order.
        //
        // This is the clause the KDoc argued and no test held, on either platform. It is
        // asserted the only way a pure surface allows: the surface is a function of the
        // library and the reading record, so if a source's state could reach a shelf, one of
        // these three would differ from the others.
        val nothing = shape(surface { false })
        val some = shape(surface { it.id == first.id })
        val everything = shape(surface { true })

        assertEquals("A shelf changed while a source was still answering.", nothing, some)
        assertEquals("A shelf changed when the source finished answering.", some, everything)
    }

    @Test
    fun `the surface has something to draw before any source has answered`() {
        // "Complete and immediately" -- there is no partial state for a slow source to
        // complete, because there is no state a source contributes to. A surface that were
        // bare with everything down would be the Plex failure exactly: a reader's own
        // history withheld until a server agrees to it.
        val down = surface { false }

        assertFalse(down.isBare)
        assertTrue(down.keepReading.isNotEmpty())
        assertTrue(down.recentlyAdded.isNotEmpty())
        assertTrue(down.finished.isNotEmpty())
    }

    private fun issue(series: String, number: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$series-$number.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = "$series $number",
        series = series,
        number = number,
        origin = MetadataOrigin.EMBEDDED,
        addedAtEpochMillis = NOW,
    )

    private fun partRead(at: Long) = ReadingProgress(
        identity = PublicationIdentity(),
        position = ReadingPosition.Page(index = 4, total = 31),
        updatedAtEpochMillis = at,
    )

    private fun finished(at: Long) = ReadingProgress(
        identity = PublicationIdentity(),
        position = ReadingPosition.Page(index = 30, total = 31),
        isFinished = true,
        finishedAtEpochMillis = at,
        updatedAtEpochMillis = at,
    )
}
