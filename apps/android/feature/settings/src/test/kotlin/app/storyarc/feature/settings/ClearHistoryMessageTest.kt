package app.storyarc.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * What the clear-history confirmation says about a server.
 *
 * The confirmation named the files, the libraries and the settings it left untouched, and
 * said nothing about a Kavita server's own progress -- which the clear never touches
 * either, so a reader with a synchronising source had every reason to read the silence as
 * "everywhere". iOS mirrors this in `ClearHistoryMessageTests`.
 */
class ClearHistoryMessageTest {

    @Test
    fun `with no synchronising source, only the body is shown`() {
        assertEquals(
            listOf(R.string.privacy_clear_history_body),
            clearHistoryMessageResIds(hasSynchronizingSource = false),
        )
    }

    @Test
    fun `with one, the server sentence follows the body`() {
        assertEquals(
            listOf(R.string.privacy_clear_history_body, R.string.privacy_clear_history_server_note),
            clearHistoryMessageResIds(hasSynchronizingSource = true),
        )
    }
}
