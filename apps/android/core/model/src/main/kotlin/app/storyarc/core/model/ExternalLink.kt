package app.storyarc.core.model

import java.net.URI

/**
 * A link out of a publication, and where it says it goes.
 *
 * A book is untrusted input, and `ebook-reader` hands an external link to the system rather
 * than opening it over the text. Handed *anything*, that is a publication choosing which
 * installed app runs and with which parameters: `<a href="someapp://action?x=y">` under
 * innocuous link text, tapped once. So only the web is accepted, and the host is carried out
 * with it so the reader can be told where they are about to go.
 *
 * A domain rule rather than a rendering one, which is why it lives here and not in the EPUB
 * reader: it is testable on the JVM, and both readers ask the same question.
 *
 * iOS's `ExternalLink` is the same type.
 */
data class ExternalLink(
    /** The address, unchanged. Only ever `http` or `https`. */
    val url: String,
    /**
     * The host as a reader would read it, for the sentence that asks them.
     *
     * `www.` is dropped because it is not information: a confirmation that says
     * "www.example.com" and one that says "example.com" describe the same destination, and
     * the shorter one is the one somebody actually reads.
     */
    val host: String,
) {
    companion object {
        private val WEB = setOf("http", "https")

        /** Null for anything that is not a web address -- which is the whole point. */
        fun of(url: String): ExternalLink? = runCatching {
            val uri = URI(url)
            val scheme = uri.scheme?.lowercase() ?: return@runCatching null
            val host = uri.host?.lowercase() ?: return@runCatching null
            if (scheme !in WEB || host.isEmpty()) return@runCatching null
            ExternalLink(url, host.removePrefix("www."))
        }.getOrNull()
    }
}
