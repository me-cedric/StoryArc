package app.storyarc.core.catalogue

import java.net.URI

/**
 * Reads a response body as an OPDS feed, whichever of the two OPDS dialects it is.
 *
 * `opds-catalog`: the app detects the version "from the response rather than requiring the
 * user to declare it". Nobody who has a catalogue URL knows whether their server speaks
 * Atom or JSON, and asking is a question with no good answer.
 */
object OpdsDocument {

    /**
     * Parses a body, using the declared content type as a hint and the bytes as the
     * authority.
     *
     * The content type is only a hint on purpose. Servers that get it wrong are common:
     * several return `text/xml` for an Atom feed and at least one returns
     * `application/octet-stream` for both. The first non-whitespace byte is not wrong.
     */
    fun parse(body: ByteArray, contentType: String? = null, baseUrl: String): OpdsFeed {
        val first = body.firstOrNull { !it.toInt().toChar().isWhitespace() }
            ?: throw OpdsError.Empty

        return when (first.toInt().toChar()) {
            '{' -> OpdsJson.parse(body, baseUrl)
            '<' -> {
                // An HTML page is also angle-bracketed, and is what a misconfigured server
                // or a login wall returns. Named here rather than left to the Atom parser,
                // which would report a missing element and send the reader looking for the
                // wrong thing.
                if (looksLikeHtml(body)) throw OpdsError.NotAFeed(OpdsError.Received.Html)
                OpdsAtom.parse(body, baseUrl)
            }
            else -> throw OpdsError.NotAFeed(OpdsError.Received.Unrecognised(contentType))
        }
    }

    /**
     * Whether the body opens an HTML document rather than an XML one.
     *
     * Looks only at the head of the body: an Atom feed can legitimately *contain* the word
     * `html`, in a summary or an XHTML content element, and scanning the whole document
     * would call that page HTML.
     */
    private fun looksLikeHtml(body: ByteArray): Boolean {
        val head = String(body, 0, minOf(512, body.size)).lowercase()
        if (head.contains("<!doctype html") || head.contains("<html")) return true
        // An XML declaration followed by an XHTML root is still a page, not a feed.
        return head.contains("<?xml") && head.contains("xhtml")
    }

    /**
     * A possibly relative href, made absolute against the feed it came from.
     *
     * Braces are swapped out and back. A search template carries `{searchTerms}`, braces
     * are not legal in a URI, and `URI.resolve` throws on one — which silently dropped
     * every templated search link.
     */
    internal fun resolve(href: String, baseUrl: String): String? = runCatching {
        val guarded = href.replace("{", "%7B").replace("}", "%7D")
        URI(baseUrl).resolve(guarded).toString().replace("%7B", "{").replace("%7D", "}")
    }.getOrNull()
}
