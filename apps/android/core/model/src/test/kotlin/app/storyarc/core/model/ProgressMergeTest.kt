package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * The table in ADR-0006, asserted row by row. iOS's `ProgressMergeTests`
 * asserts the same rows, which is how the two implementations stay honest about
 * the one rule a user would actually notice getting wrong.
 */
class ProgressMergeTest {
    private val identity = PublicationIdentity(contentDigest = "abc123")
    private val epoch = 1_700_000_000_000L

    private fun progress(
        page: Int,
        total: Int = 100,
        finished: Boolean = false,
        synced: Int? = null,
    ) = ReadingProgress(
        identity = identity,
        position = ReadingPosition.Page(page, total),
        isFinished = finished,
        updatedAtEpochMillis = epoch,
        syncedPosition = synced?.let { ReadingPosition.Page(it, total) },
    )

    @Test
    fun `remote ahead and local untouched adopts remote silently`() {
        val local = progress(page = 10, synced = 10)
        val remote = progress(page = 40)

        assertEquals(ProgressMergeOutcome.AdoptRemote(remote), ProgressMerge.merge(local, remote))
    }

    @Test
    fun `remote behind local keeps local and pushes it`() {
        val local = progress(page = 40, synced = 10)
        val remote = progress(page = 10)

        assertEquals(ProgressMergeOutcome.KeepLocalAndPush(local), ProgressMerge.merge(local, remote))
    }

    @Test
    fun `both moved resolves to the further position and reports the conflict`() {
        val local = progress(page = 30, synced = 10)
        val remote = progress(page = 55)

        assertEquals(
            ProgressMergeOutcome.Conflict(remote, ReadingPosition.Page(30, 100)),
            ProgressMerge.merge(local, remote),
        )
    }

    @Test
    fun `a conflict where local is further keeps local and still reports it`() {
        val local = progress(page = 70, synced = 10)
        val remote = progress(page = 55)

        assertEquals(
            ProgressMergeOutcome.Conflict(local, ReadingPosition.Page(55, 100)),
            ProgressMerge.merge(local, remote),
        )
    }

    @Test
    fun `finished wins over a further partial position`() {
        // Remote is finished but sits at page 0; local is untouched at page 90.
        // Position alone would keep local. Finished must still win.
        val local = progress(page = 90, synced = 10)
        val remote = progress(page = 0, finished = true)

        assertEquals(ProgressMergeOutcome.AdoptRemote(remote), ProgressMerge.merge(local, remote))
    }

    @Test
    fun `a locally finished publication is never unmarked by a partial remote`() {
        val local = progress(page = 99, finished = true, synced = 10)
        val remote = progress(page = 5)

        assertEquals(ProgressMergeOutcome.KeepLocalAndPush(local), ProgressMerge.merge(local, remote))
    }

    @Test
    fun `identical positions are not treated as a conflict`() {
        val local = progress(page = 30, synced = 10)
        val remote = progress(page = 30)

        assertEquals(ProgressMergeOutcome.KeepLocalAndPush(local), ProgressMerge.merge(local, remote))
    }

    @Test
    fun `a never-synced local record is treated as moved`() {
        val local = progress(page = 20, synced = null)
        val remote = progress(page = 60)

        assertEquals(
            ProgressMergeOutcome.Conflict(remote, ReadingPosition.Page(20, 100)),
            ProgressMerge.merge(local, remote),
        )
    }

    @Test
    fun `a synced position a store kept as a bare fraction still counts as untouched`() {
        // What the Room row hands back: the fraction survived, the page did not. Compared by
        // case, this could never equal the position it was stored from, and the first row of
        // the table above was unreachable.
        val local = progress(page = 10).copy(
            syncedPosition = ReadingPosition.Reflowable(ReadingPosition.Page(10, 100).fraction, ""),
        )
        val remote = progress(page = 40)

        assertEquals(ProgressMergeOutcome.AdoptRemote(remote), ProgressMerge.merge(local, remote))
    }

    @Test
    fun `a synced position kept as a fraction still says when the server has not moved`() {
        val local = progress(page = 40).copy(
            syncedPosition = ReadingPosition.Reflowable(ReadingPosition.Page(10, 100).fraction, ""),
        )
        val remote = progress(page = 10)

        assertEquals(ProgressMergeOutcome.KeepLocalAndPush(local), ProgressMerge.merge(local, remote))
    }

    @Test
    fun `first page is zero and last page is one`() {
        assertEquals(0.0, ReadingPosition.Page(0, 100).fraction, 0.0001)
        assertEquals(1.0, ReadingPosition.Page(99, 100).fraction, 0.0001)
    }

    @Test
    fun `a single-page publication does not divide by zero`() {
        assertEquals(1.0, ReadingPosition.Page(0, 1).fraction, 0.0001)
    }

    @Test
    fun `reflowable progression is clamped`() {
        assertEquals(0.0, ReadingPosition.Reflowable(-0.5, "x").fraction, 0.0001)
        assertEquals(1.0, ReadingPosition.Reflowable(1.5, "x").fraction, 0.0001)
    }

    @Test
    fun `a matching content digest resolves two records to the same publication`() {
        val fromFolder = PublicationIdentity(contentDigest = "d1", normalizedPath = "/a/b.cbz")
        val fromShare = PublicationIdentity(contentDigest = "d1", normalizedPath = "//nas/x.cbz")

        assertTrue(fromFolder.matches(fromShare))
    }

    @Test
    fun `a file that later gains a server id still matches its digest record`() {
        val local = PublicationIdentity(contentDigest = "d1")
        val server = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(UUID.randomUUID(), "42"),
            contentDigest = "d1",
        )

        assertTrue(local.matches(server))
    }

    @Test
    fun `the same remote id on two different servers is not the same publication`() {
        val a = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(UUID.randomUUID(), "42"),
        )
        val b = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(UUID.randomUUID(), "42"),
        )

        assertFalse(a.matches(b))
    }

    @Test
    fun `an identity with nothing recorded is empty and matches nothing`() {
        val empty = PublicationIdentity()

        assertTrue(empty.isEmpty)
        assertFalse(empty.matches(PublicationIdentity(contentDigest = "d1")))
    }

    // The filing key.

    @Test
    fun `learning a digest does not re-file a publication`() {
        // Collection members, reading-list entries, a download's id and the folder its
        // bytes live in, and Kavita's chapter-to-publication table all hold this string.
        // The scanners produced a path and nothing else until the digest was wired in, so
        // a key that moved when the digest arrived would empty every shelf and orphan
        // every downloaded file on one launch.
        val beforeTheDigest = PublicationIdentity(normalizedPath = "/lib/Bone 01.cbz")
        val afterTheDigest = beforeTheDigest.recordingDigest("d1")

        assertEquals("d1", afterTheDigest.contentDigest)
        assertEquals(beforeTheDigest.stableId, afterTheDigest.stableId)
    }

    @Test
    fun `a file with no path of its own is still filed under its digest`() {
        // What a file handed over from outside the app gets: no path this app is entitled
        // to keep, so the digest is the only key there is.
        assertEquals("sha:d1", PublicationIdentity(contentDigest = "d1").stableId)
    }

    @Test
    fun `a server identifier outranks both, because the server owns its own content`() {
        val sourceId = UUID.randomUUID()
        val identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(sourceId, "42"),
            contentDigest = "d1",
            normalizedPath = "/lib/Bone 01.cbz",
        )

        assertEquals("srv:$sourceId:42", identity.stableId)
    }

    @Test
    fun `a digest already recorded is not overwritten by a later one`() {
        // Whoever supplied the first one knew something this caller does not — a caller
        // passing an identity in is entitled to have it respected.
        val known = PublicationIdentity(contentDigest = "d1", normalizedPath = "/a/b.cbz")

        assertEquals("d1", known.recordingDigest("d2").contentDigest)
        assertEquals("d1", known.recordingDigest(null).contentDigest)
    }

    @Test
    fun `a digest that could not be taken leaves the identity as it was`() {
        // A directory, or a file that would not open. Indexing must not fail over it: the
        // publication keys on its path, exactly where it stood before.
        val pathOnly = PublicationIdentity(normalizedPath = "/a/b.cbz")

        assertEquals(pathOnly, pathOnly.recordingDigest(null))
    }
}

class SourceStateTest {
    @Test
    fun `only an unauthorized source asks the user to do something`() {
        assertFalse(SourceConnectionState.Connected.needsUserAction)
        assertFalse(SourceConnectionState.Connecting.needsUserAction)
        assertFalse(SourceConnectionState.Unreachable(0L).needsUserAction)
        assertTrue(SourceConnectionState.Unauthorized("401").needsUserAction)
    }

    @Test
    fun `only a connected source can fetch content it has not downloaded`() {
        assertTrue(SourceConnectionState.Connected.canFetch)
        assertFalse(SourceConnectionState.Unreachable(0L).canFetch)
    }

    @Test
    fun `backoff starts at five seconds, doubles, and caps at five minutes`() {
        assertEquals(5_000L, ReconnectBackoff.delayMillis(1))
        assertEquals(10_000L, ReconnectBackoff.delayMillis(2))
        assertEquals(40_000L, ReconnectBackoff.delayMillis(4))
        assertEquals(300_000L, ReconnectBackoff.delayMillis(20))
    }
}

class ReadingPreferenceTest {
    @Test
    fun `japanese with no declared direction opens right to left`() {
        assertEquals(ReadingDirection.RIGHT_TO_LEFT, ReadingDirection.inferred(null, "ja"))
        assertEquals(ReadingDirection.RIGHT_TO_LEFT, ReadingDirection.inferred(null, "ja-JP"))
    }

    @Test
    fun `a declared direction always wins over the language guess`() {
        assertEquals(
            ReadingDirection.LEFT_TO_RIGHT,
            ReadingDirection.inferred(ReadingDirection.LEFT_TO_RIGHT, "ja"),
        )
    }

    @Test
    fun `an unknown language defaults to left to right`() {
        assertEquals(ReadingDirection.LEFT_TO_RIGHT, ReadingDirection.inferred(null, null))
    }

    @Test
    fun `reduce motion downgrades the animated transitions to a cross-dissolve`() {
        assertEquals(PageTransition.FAST_FADE, PageTransition.PAGE_CURL.honoring(reduceMotion = true))
        assertEquals(PageTransition.FAST_FADE, PageTransition.SLIDE.honoring(reduceMotion = true))
        assertEquals(
            PageTransition.VERTICAL_SCROLL,
            PageTransition.VERTICAL_SCROLL.honoring(reduceMotion = true),
        )
        assertEquals(PageTransition.PAGE_CURL, PageTransition.PAGE_CURL.honoring(reduceMotion = false))
    }
}
