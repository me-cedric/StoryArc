package app.storyarc.core.smb

import jcifs.config.PropertyConfiguration
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The client asks for signing, rather than waiting to be told to.
 *
 * The security review's rank 16. jcifs-ng signs only when the negotiated session says it
 * must, and a consumer NAS that merely *supports* signing -- the common default -- says it
 * must not. So the session was unsigned, and an attacker on the LAN could rewrite a
 * QUERY_DIRECTORY or a READ response and feed a crafted archive straight into the format
 * layer, which is this app's primary attack surface.
 *
 * `signingPreferred` is the fix: sign wherever the server can. Configuration rather than a
 * live connection, because what went wrong was a property that was never set -- and
 * `SmbClientTest`'s server-backed suite skips itself when no server is running, which is
 * exactly when this would go unnoticed again.
 */
class SmbSigningTest {

    private val config = PropertyConfiguration(SmbClient.clientProperties())

    @Test
    fun `signing is requested, so a server that merely supports it gets a signed session`() {
        assertTrue("jcifs.smb.client.signingPreferred", config.isSigningEnabled)
    }

    /**
     * Not enforced, and that is the deliberate half.
     *
     * `network-share` requires a guest share to work, and a guest session is unsigned by
     * definition. Enforcing would refuse it -- which is a product decision about which
     * shares StoryArc supports, not a security fix, and it belongs in a proposal rather than
     * here. Preferring costs nothing and covers every server that can sign.
     */
    @Test
    fun `signing is not enforced, because a guest share cannot sign at all`() {
        assertFalse("jcifs.smb.client.signingEnforced", config.isSigningEnforced)
    }

    @Test
    fun `the dialect floor is unchanged, so signing is not bought with SMB 1`() {
        assertTrue(config.minimumVersion.atLeast(jcifs.DialectVersion.SMB202))
    }
}
