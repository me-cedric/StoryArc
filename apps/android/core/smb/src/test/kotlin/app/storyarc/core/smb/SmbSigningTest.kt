package app.storyarc.core.smb

import com.hierynomus.mssmb2.SMB2Dialect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the client asks for before it knows anything about the server.
 *
 * The security review's rank 16 was a client that signed only where the server insisted.
 * smbj signs every request of a session that has a key and checks every response, so the
 * setting to guard is that signing stays enabled. Configuration rather than a live
 * connection, because `SmbClientTest`'s server-backed suite skips itself when no server is
 * running, which is exactly when a lost setting would go unnoticed.
 */
class SmbSigningTest {

    private val config = SmbClient.clientConfig()

    @Test
    fun `signing is enabled, so a server that merely supports it gets a signed session`() {
        assertTrue("signing enabled", config.isSigningEnabled)
    }

    /**
     * Not enforced, and that is the deliberate half.
     *
     * `network-share` requires a guest share to work, and a guest session is unsigned by
     * definition. Enforcing would refuse it.
     */
    @Test
    fun `signing is not enforced, because a guest share cannot sign at all`() {
        assertFalse("signing required", config.isSigningRequired)
    }

    /**
     * SMB 3 is offered, so a server that supports encryption gets it.
     *
     * `network-share`'s *Encrypted transport*: "WHEN the server supports SMB 3 encryption
     * THEN the app negotiates it". jcifs-ng offered SMB 3 and had no cipher. smbj has the
     * cipher, and it is used only when SMB 3 is what the two ends agree.
     */
    @Test
    fun `every SMB 3 dialect is offered, beside SMB 2`() {
        assertEquals(
            setOf(
                SMB2Dialect.SMB_3_1_1,
                SMB2Dialect.SMB_3_0_2,
                SMB2Dialect.SMB_3_0,
                SMB2Dialect.SMB_2_1,
                SMB2Dialect.SMB_2_0_2,
            ),
            config.supportedDialects.toSet(),
        )
    }

    /**
     * Encryption is offered. Without the capability a server never picks a cipher, and the
     * session stays in clear even where the server could encrypt it.
     */
    @Test
    fun `encryption is offered, so a server that can encrypt does`() {
        assertTrue("encryption offered", config.isEncryptData)
    }

    @Test
    fun `SMB 1 is never offered, so signing and encryption are not bought with it`() {
        assertFalse("multi-protocol negotiate sends an SMB 1 packet", config.isUseMultiProtocolNegotiate)
    }
}
