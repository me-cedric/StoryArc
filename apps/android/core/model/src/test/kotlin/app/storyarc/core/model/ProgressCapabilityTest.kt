package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which sources can hold a reading position, and which three have to say they cannot.
 *
 * `reading-progress`' *Source cannot store progress*: "progress is kept locally only, and the
 * source detail screen states that progress for it does not sync". The sentence was never said
 * on either platform, and this is the decision it turns on. iOS's `ProgressCapabilityTests`
 * asserts the same four cases.
 */
class ProgressCapabilityTest {

    @Test
    fun `kavita is the one source that keeps a position of its own`() {
        // Not a preference: `KavitaSync` is the only code in either app that pushes or pulls
        // a position, so this list is the list of sources that have a mechanism.
        assertTrue(SourceKind.KAVITA_SERVER.syncsReadingProgress)
    }

    @Test
    fun `a folder, a share and an OPDS catalogue keep nothing`() {
        // A folder and a share are files on a disk with nowhere to write a position to, and
        // OPDS is a catalogue format that has no notion of one. All three are situations the
        // reader must be told about rather than left to assume from the word "sync".
        assertFalse(SourceKind.LOCAL_FOLDER.syncsReadingProgress)
        assertFalse(SourceKind.NETWORK_SHARE.syncsReadingProgress)
        assertFalse(SourceKind.OPDS_CATALOG.syncsReadingProgress)
    }

    @Test
    fun `exactly one of the four syncs, so a fifth kind cannot default into silence`() {
        // The same guard `isBrowsable` carries: the property is a `when` over every case, so
        // a new kind fails to compile rather than being quietly assumed to sync -- which
        // would drop the sentence for it and let a reader assume their place is safe.
        assertEquals(
            listOf(SourceKind.KAVITA_SERVER),
            SourceKind.entries.filter { it.syncsReadingProgress },
        )
    }
}
