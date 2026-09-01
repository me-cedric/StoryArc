package app.storyarc.feature.library

import app.storyarc.feature.library.SkippedPublications.Entry
import app.storyarc.feature.library.SkippedPublications.Notice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The rules behind the notice that replaced *"2 couldn't be opened"*.
 *
 * Every one of these was true of nothing before: the count had no state, so there was
 * nothing to assert about it beyond that it rendered. What is asserted here is the whole
 * substance of the replacement — which sentence a reader gets, whether a set they dismissed
 * comes back, and when an entry leaves the list.
 *
 * The two fixtures are the corpus files that fail *differently*: `refused.cb7` is a
 * container StoryArc does not read, `password-protected.cbz` is a ZIP it does read whose
 * entries it cannot. The change's task list names `rar4-solid.cbr` for this and it is the
 * wrong file — a solid RAR4 is *found* and marked unopenable on purpose, so it never
 * reaches a skip. `SkippedScanTest` proves the pair against the real scanner.
 *
 * iOS asserts the same cases in `SkippedPublicationsTests`.
 */
class SkippedPublicationsTest {

    private val sevenZip = Entry("refused.cb7", "CB7 is not a format StoryArc reads")
    private val protected = Entry("password-protected.cbz", "the archive is password protected")

    @Test
    fun `nothing failed nothing is said`() {
        assertEquals(Notice.Nothing, SkippedPublications().notice)
        // And a scan that met nothing does not leave a notice from the one before it.
        assertEquals(
            Notice.Nothing,
            SkippedPublications().settling(listOf(sevenZip)).settling(emptyList()).notice,
        )
    }

    @Test
    fun `one failure names its publication and its reason`() {
        // The delta spec: "the notice names that publication and states the reason in the
        // words `publication-formats` gives for it". Not a count, and not a sentence this
        // layer wrote.
        assertEquals(
            Notice.One("refused.cb7", "CB7 is not a format StoryArc reads"),
            SkippedPublications().settling(listOf(sevenZip)).notice,
        )
    }

    @Test
    fun `several state the count and keep every reason apart`() {
        val skipped = SkippedPublications().settling(listOf(sevenZip, protected))

        assertEquals(Notice.Several(2), skipped.notice)
        // "the reasons are not merged: two files that failed differently say different
        // things". The count is the notice; the reasons are the list behind it.
        assertEquals(listOf("refused.cb7", "password-protected.cbz"), skipped.entries.map { it.name })
        assertEquals(2, skipped.entries.map { it.reason }.toSet().size)
    }

    @Test
    fun `dismissal is the reader's and the list stays reachable`() {
        val skipped = SkippedPublications().settling(listOf(sevenZip, protected)).dismissing()

        // Not `Nothing`: the notice has gone and the way to the list has not.
        assertEquals(Notice.Reachable, skipped.notice)
        assertEquals(2, skipped.entries.size)
    }

    @Test
    fun `the same set does not announce itself twice`() {
        val dismissed = SkippedPublications().settling(listOf(sevenZip, protected)).dismissing()

        // A second scan of the same library meets the same two files. Nothing changed, so
        // there is nothing to say again — announcing anyway was the toast's own failure.
        assertEquals(Notice.Reachable, dismissed.settling(listOf(sevenZip, protected)).notice)
        // Order is not the set. The same two files met the other way round are still the
        // same two files.
        assertEquals(Notice.Reachable, dismissed.settling(listOf(protected, sevenZip)).notice)
    }

    @Test
    fun `a set that grows announces itself again`() {
        val dismissed = SkippedPublications().settling(listOf(sevenZip)).dismissing()

        // "the count is not shown again for the same publications **unless the set
        // changes**". It changed.
        assertEquals(Notice.Several(2), dismissed.settling(listOf(sevenZip, protected)).notice)
    }

    @Test
    fun `a publication that later opens leaves the list without being dismissed`() {
        val both = SkippedPublications().settling(listOf(sevenZip, protected))
        // The archive was re-downloaded unprotected, so the next walk does not report it.
        val one = both.settling(listOf(sevenZip))

        assertEquals(listOf("refused.cb7"), one.entries.map { it.name })
        assertEquals(Notice.One(sevenZip.name, sevenZip.reason), one.notice)
    }

    @Test
    fun `the notice goes when the list empties`() {
        val both = SkippedPublications().settling(listOf(sevenZip, protected))
        // Both fixed. Without this the list becomes a record of problems that were solved
        // weeks ago, and a reader learns to ignore it — which is the toast's failure arrived
        // at slowly.
        assertEquals(Notice.Nothing, both.settling(emptyList()).notice)
        assertTrue(both.settling(emptyList()).entries.isEmpty())
    }

    @Test
    fun `a publication fixed and then broken again is news a second time`() {
        val dismissed = SkippedPublications().settling(listOf(sevenZip)).dismissing()
        // Gone from the list, so the acknowledgement goes with it: keeping it would make a
        // file that broke a second time silent for ever.
        val fixed = dismissed.settling(emptyList())

        assertEquals(
            Notice.One(sevenZip.name, sevenZip.reason),
            fixed.settling(listOf(sevenZip)).notice,
        )
    }

    @Test
    fun `one file met twice in one scan is one row`() {
        // A tree walked under two sources reports the same document twice, and "2 couldn't
        // be opened" for one file is worse than the count it replaced.
        val skipped = SkippedPublications().settling(listOf(sevenZip, sevenZip))

        assertEquals(1, skipped.entries.size)
        assertEquals(Notice.One(sevenZip.name, sevenZip.reason), skipped.notice)
    }
}
