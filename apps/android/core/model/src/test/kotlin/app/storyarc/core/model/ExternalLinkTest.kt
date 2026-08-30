package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Which addresses a publication is allowed to send the reader to.
 *
 * A book is untrusted input. `<a href="someapp://do?x=y">Continue reading -></a>` under
 * innocuous link text launches whatever registered that scheme with the parameters the book
 * chose, and the reader never sees where they were going.
 *
 * iOS's `ExternalLinkTests` asserts the same cases in the same order.
 */
class ExternalLinkTest {

    @Test
    fun aWebAddressIsOfferedWithItsHostNamed() {
        val leaving = requireNotNull(ExternalLink.of("https://example.com/notes/1"))
        assertEquals("example.com", leaving.host)
        assertEquals("https://example.com/notes/1", leaving.url)
    }

    @Test
    fun cleartextIsStillTheReadersToRefuse() {
        // Not a security decision this app makes for them: a link to a plain-HTTP page is an
        // ordinary web page, and the host is shown either way.
        val leaving = requireNotNull(ExternalLink.of("http://nas.local/index.html"))
        assertEquals("nas.local", leaving.host)
    }

    @Test
    fun aWwwPrefixIsShownAsTheReaderWouldReadIt() {
        assertEquals("example.com", requireNotNull(ExternalLink.of("https://www.example.com/x")).host)
    }

    @Test
    fun anythingThatIsNotTheWebIsDropped() {
        assertNull(ExternalLink.of("someinstalledapp://action?param=chosen"))
        assertNull(ExternalLink.of("tel:+15551234567"))
        assertNull(ExternalLink.of("sms:+15551234567"))
        assertNull(ExternalLink.of("mailto:reader@example.com"))
        assertNull(ExternalLink.of("intent://scan/#Intent;scheme=zxing;end"))
        assertNull(ExternalLink.of("file:///etc/hosts"))
        assertNull(ExternalLink.of("javascript:alert(1)"))
    }

    @Test
    fun anAddressWithNoHostIsNotSomewhereToGo() {
        assertNull(ExternalLink.of("https:///nowhere"))
        assertNull(ExternalLink.of("not a url at all"))
    }
}
