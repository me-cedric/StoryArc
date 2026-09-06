package app.storyarc.feature.library

import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.smb.SmbError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What a share's refusal leaves the source saying.
 *
 * `network-share` asks the app to "report the specific failure" when a share refuses. The
 * add-a-share sheet does that; the health probe behind a share already saved sent every
 * refusal but a rejected password to `Unreachable`, so a share that demands SMB 3 encryption
 * read "No answer since ...". The server answered. It refused, for a reason the reader can act
 * on, and `sources` re-asks an unreachable source every 5 s rising to every 5 minutes -- so
 * the wrong state also asked a share that can never say yes, for as long as the library was on
 * screen.
 *
 * iOS's `SmbSourceStateTests` holds this table case for case.
 */
class SmbSourceStateTest {

    private fun state(error: SmbError) = SmbSourceState.of(error, MOMENT, PASSWORD, ENCRYPTION)

    @Test
    fun `a share that demands encryption says so, and is not called unreachable`() {
        assertEquals(SourceConnectionState.Unauthorized(ENCRYPTION), state(SmbError.EncryptionRequired))
    }

    @Test
    fun `the refusal a reader can act on is not the one about a password`() {
        assertTrue(
            "an encrypted share was blamed on the password again",
            state(SmbError.EncryptionRequired) != state(SmbError.AuthenticationRejected),
        )
        assertEquals(SourceConnectionState.Unauthorized(PASSWORD), state(SmbError.AuthenticationRejected))
    }

    @Test
    fun `a share that did not answer is unreachable, and keeps the moment it went`() {
        val away = SourceConnectionState.Unreachable(MOMENT)
        assertEquals(away, state(SmbError.HostUnreachable))
        assertEquals(away, state(SmbError.ShareNotFound))
        assertEquals(away, state(SmbError.Unexpected("x")))
    }

    @Test
    fun `an SMB 1 server is offline rather than something the reader must fix here`() {
        // Offline is a normal state. `ProtocolUnsupported` is the app's own refusal to speak
        // SMB 1, and the add-a-share sheet is where that sentence belongs -- a saved share
        // that turns out to be SMB 1 is grey, not a badge asking for action.
        assertEquals(SourceConnectionState.Unreachable(MOMENT), state(SmbError.ProtocolUnsupported))
    }

    private companion object {
        const val MOMENT = 1_000L
        const val PASSWORD = "the password was refused"
        const val ENCRYPTION = "this server requires SMB 3 encryption"
    }
}
