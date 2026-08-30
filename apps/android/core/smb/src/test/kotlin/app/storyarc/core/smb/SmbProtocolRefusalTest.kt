package app.storyarc.core.smb

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A server that offers only SMB 1 is refused, and named.
 *
 * `network-share` wants the refusal to say which server setting to change, rather than a
 * fifth way of saying "could not connect". jcifs never reaches an NT status for it -- the
 * two ends fail to agree a dialect before the server answers with one -- so the reading is
 * of what jcifs itself said. The three sentences asserted here are jcifs-ng 2.1.10's own,
 * read out of the shipped classes rather than guessed.
 *
 * Mirrored case for case by `SmbProtocolRefusalTests.swift`, which reads NT statuses
 * instead because the Swift client does reach one.
 */
class SmbProtocolRefusalTest {

    @Test
    fun `a server that would not agree a dialect is named as SMB 1`() {
        assertEquals(SmbError.ProtocolUnsupported, fromMessage("Server returned an unknown dialect"))
        assertEquals(
            SmbError.ProtocolUnsupported,
            fromMessage("Server selected an disallowed dialect version SMB1 (min: SMB202 max: SMB311)"),
        )
        assertEquals(
            SmbError.ProtocolUnsupported,
            fromMessage("Server returned invalid dialect verison in multi protocol negotiation"),
        )
    }

    @Test
    fun `a failure that is not about the dialect is not named as SMB 1`() {
        assertEquals(
            SmbError.EncryptionRequired,
            fromMessage("Server requires encryption, not yet supported."),
        )
    }

    @Test
    fun `a failure nothing recognises keeps what was said, rather than guessing`() {
        val thrown = fromMessage("Connection reset by peer")
        assertEquals(SmbError.Unexpected("Connection reset by peer"), thrown)
    }

    @Test
    fun `a refusal with nothing to say still reads as a refusal`() {
        assertTrue(fromMessage("", fallback = SmbError.HostUnreachable) is SmbError.HostUnreachable)
    }
}
