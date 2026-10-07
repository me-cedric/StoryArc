package app.storyarc.core.smb

import com.hierynomus.mssmb.SMB1NotSupportedException
import com.hierynomus.protocol.transport.TransportException
import com.hierynomus.smbj.common.SMBRuntimeException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A failure is named as one of the failures `network-share` names, and not guessed.
 *
 * smbj fails a connect in three shapes: an NT status from the server, a cause buried under
 * its own wrapper, or a sentence. Each is read here in that order.
 *
 * Mirrored case for case by `SmbProtocolRefusalTests.swift`, which reads NT statuses.
 */
class SmbProtocolRefusalTest {

    @Test
    fun `a refused password is named from its NT status`() {
        assertEquals(SmbError.AuthenticationRejected, meaning(0xC000006DL))
        assertEquals(SmbError.AuthenticationRejected, meaning(0xC000006AL))
        assertEquals(SmbError.AuthenticationRejected, meaning(0xC0000022L))
    }

    @Test
    fun `a missing share is named from its NT status, and a missing file is not`() {
        assertEquals(SmbError.ShareNotFound, meaning(0xC00000CCL))
        assertEquals(SmbError.ShareNotFound, meaning(0xC000003AL))
        // OBJECT_NAME_NOT_FOUND is a missing file, not a missing share.
        assertNull(meaning(0xC0000034L))
    }

    @Test
    fun `a server that speaks only SMB 1 is named as such, from smbj's own exception`() {
        val wrapped = SMBRuntimeException(TransportException(SMB1NotSupportedException()))
        assertEquals(SmbError.ProtocolUnsupported, fromCauseChain(wrapped))
        assertEquals(SmbError.ProtocolUnsupported, translate(wrapped))
    }

    @Test
    fun `a session that cannot meet a demand for encryption is named as such`() {
        assertEquals(
            SmbError.EncryptionRequired,
            fromMessage("Message encryption is required, but no encryption key is negotiated"),
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

    @Test
    fun `an unreachable host is read from a cause the outer wrapper does not name`() {
        val refusedConnect = SMBRuntimeException(ConnectException("Connection refused"))
        assertEquals(SmbError.HostUnreachable, fromCauseChain(refusedConnect))

        val unknownHost = TransportException(UnknownHostException("nas.invalid"))
        assertEquals(SmbError.HostUnreachable, fromCauseChain(unknownHost))

        val noRoute = SMBRuntimeException(NoRouteToHostException("No route to host"))
        assertEquals(SmbError.HostUnreachable, fromCauseChain(noRoute))

        val timedOut = SMBRuntimeException(SocketTimeoutException("connect timed out"))
        assertEquals(SmbError.HostUnreachable, fromCauseChain(timedOut))
    }

    @Test
    fun `a cause chain with nothing recognisable answers nothing, rather than guessing`() {
        assertNull(fromCauseChain(SMBRuntimeException(RuntimeException("weird"))))
    }
}
