package app.storyarc.core.kavita

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/** The exact address a reader types on an emulator, which reaches the host loopback. */
class EmulatorAddressTest {
    @Test
    fun `reads a loopback address with a port`() {
        val address = KavitaAddress.fromOpds("http://10.0.2.2:5001/api/opds/storyarc-test-key")
        assertNotNull(address)
        assertEquals("http://10.0.2.2:5001", address?.base)
        assertEquals("storyarc-test-key", address?.apiKey)
    }
}
