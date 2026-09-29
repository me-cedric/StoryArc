package app.storyarc.feature.reader

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [needsRecovery] -- the rule [ReaderViewModel.watchForPageRecovery] polls against, lifted
 * so a test can hold it without a publication to wait on.
 *
 * `network-share`'s *Connection drops while reading*: "resume streaming at the current
 * page" after reconnecting. `warm`'s only other caller is `noteMemoryPressure`, which does
 * not fire on its own while the reader sits on one page -- so a page that failed stayed a
 * spinner until a turn away and back asked for it again. This is the condition that decides
 * when the periodic retry should actually ask. iOS's `PageRecoveryTests` is the same rule.
 */
class PageRecoveryTest {

    @Test
    fun `a page neither decoded, refused, nor in flight needs a read`() {
        assertTrue(
            needsRecovery(
                currentIndex = 2,
                pageCount = 5,
                decoded = emptySet(),
                attempted = emptySet(),
                refused = emptySet(),
            ),
        )
    }

    @Test
    fun `an already-decoded page needs nothing`() {
        assertFalse(
            needsRecovery(
                currentIndex = 2,
                pageCount = 5,
                decoded = setOf(2),
                attempted = emptySet(),
                refused = emptySet(),
            ),
        )
    }

    @Test
    fun `a permanently refused page is not retried for ever`() {
        assertFalse(
            needsRecovery(
                currentIndex = 2,
                pageCount = 5,
                decoded = emptySet(),
                attempted = emptySet(),
                refused = setOf(2),
            ),
        )
    }

    @Test
    fun `a read already in flight is not asked for twice`() {
        // `decode` inserts into `attempted` before it awaits, and only a failure removes
        // the entry -- so this is the one state that distinguishes "still reading" from
        // "gave up and needs asking again".
        assertFalse(
            needsRecovery(
                currentIndex = 2,
                pageCount = 5,
                decoded = emptySet(),
                attempted = setOf(2),
                refused = emptySet(),
            ),
        )
    }

    @Test
    fun `only the current index is asked about, whatever else failed nearby`() {
        assertTrue(
            needsRecovery(
                currentIndex = 2,
                pageCount = 5,
                decoded = setOf(1, 3),
                attempted = setOf(1, 3),
                refused = emptySet(),
            ),
        )
    }

    @Test
    fun `an index outside the publication needs nothing, rather than asking forever`() {
        assertFalse(
            needsRecovery(
                currentIndex = 9,
                pageCount = 5,
                decoded = emptySet(),
                attempted = emptySet(),
                refused = emptySet(),
            ),
        )
    }
}
