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
        // Not a preference: Kavita is the only one of the four with somewhere to put a
        // position. `KavitaClient` posts one to `Reader/progress` and reads one back from
        // `Reader/continue-point`; no other source kind has either half.
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
    fun `exactly one of the four syncs, so the other three all state it`() {
        // What keeps a *fifth* kind out of silence is not this assertion. The property is a
        // `when` used as an expression, so a new case is a compile error rather than a quiet
        // `false` -- a guarantee no test can fail on, which is why it is claimed here and not
        // in the name above. This pins the answer for the four kinds that exist, and it is
        // the assertion that breaks if a case is moved to the wrong arm.
        assertEquals(
            listOf(SourceKind.KAVITA_SERVER),
            SourceKind.entries.filter { it.syncsReadingProgress },
        )
    }
}
