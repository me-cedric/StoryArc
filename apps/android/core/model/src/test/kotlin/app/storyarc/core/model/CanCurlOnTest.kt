package app.storyarc.core.model

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `page-transitions`: "the app never ships a curl that stutters in preference to a
 * slide that does not". API 33 is where AGSL's `RuntimeShader` arrives, and the comic
 * and the EPUB reader's view models both read this instead of each keeping their own
 * copy of the gate.
 */
class CanCurlOnTest {
    @Test
    fun `API 31 and 32 cannot hold the curl's refresh rate`() {
        assertFalse(canCurlOn(31))
        assertFalse(canCurlOn(32))
    }

    @Test
    fun `API 33 and later can`() {
        assertTrue(canCurlOn(33))
        assertTrue(canCurlOn(34))
    }
}
