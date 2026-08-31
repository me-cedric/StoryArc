package app.storyarc.feature.library

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The rule that decides whether *Start from the beginning* is drawn. iOS's
 * `RestartOfferTests` asserts the same cases.
 *
 * The case that matters is `isWired`. Before it, iOS's `CoverList` opened the shelf menu
 * with a trailing closure -- which binds to the first parameter with no default -- so the
 * restart handler stayed on its empty default and the button rendered regardless. The reader
 * tapped it and nothing happened, and nothing failed: a test asserting the button exists
 * would have passed. This asserts the opposite direction, which is the one that was wrong.
 */
class RestartOfferTest {
    @Test
    fun `one publication with progress and a handler is offered`() {
        assertTrue(
            RestartOffer.isOffered(
                publicationCount = 1,
                hasSomethingToClear = true,
                isWired = true,
            ),
        )
    }

    @Test
    fun `a menu with no handler draws no button`() {
        assertFalse(
            RestartOffer.isOffered(
                publicationCount = 1,
                hasSomethingToClear = true,
                isWired = false,
            ),
        )
    }

    @Test
    fun `a publication with nothing to clear is not offered`() {
        // It would start it from the beginning it is already at.
        assertFalse(
            RestartOffer.isOffered(
                publicationCount = 1,
                hasSomethingToClear = false,
                isWired = true,
            ),
        )
    }

    @Test
    fun `a selection has no single beginning to go back to`() {
        assertFalse(
            RestartOffer.isOffered(
                publicationCount = 2,
                hasSomethingToClear = true,
                isWired = true,
            ),
        )
        assertFalse(
            RestartOffer.isOffered(
                publicationCount = 0,
                hasSomethingToClear = true,
                isWired = true,
            ),
        )
    }
}
