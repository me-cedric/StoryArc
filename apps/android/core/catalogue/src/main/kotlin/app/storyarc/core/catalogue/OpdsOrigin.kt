package app.storyarc.core.catalogue

import java.net.URI

/**
 * Where a configured source lives: scheme, host and port, and nothing else.
 *
 * A catalogue chooses every address the app fetches after the first one -- the covers, the
 * next page, the acquisition link. `sources` promises that "data leaves the device only to
 * the sources the user configured", and an `Authorization` header is data. So the origin the
 * reader configured travels beside the credential, and this type is what decides whether the
 * address in front of it is that origin or somebody else's.
 *
 * Scheme, host and port together, because any one of them alone is not an origin: a
 * credential that followed `https://books.example` to `http://books.example` has gone out in
 * the clear, and one that followed it to port 8443 has gone to a different server.
 *
 * iOS's `OpdsOrigin` is the same type.
 */
data class OpdsOrigin(
    val scheme: String,
    val host: String,
    val port: Int,
) {

    /** Whether the credential for this origin may travel to this address. */
    fun admits(url: String): Boolean = of(url) == this

    /**
     * Whether following this address would step down from `https` to cleartext.
     *
     * A reader who typed `http://nas.local` meant it and is not downgraded by anything. A
     * reader who typed `https://` and is then sent to `http://` by the feed is being moved
     * somewhere they did not choose, whether by a broken proxy or a hostile one. The
     * platform will not stop it: `network_security_config.xml` permits cleartext to every
     * host so that a self-hosted server on a `.local` name stays reachable.
     */
    fun downgrades(url: String): Boolean =
        scheme == "https" && runCatching { URI(url).scheme?.lowercase() }.getOrNull() == "http"

    companion object {
        /** The only two schemes this app fetches over. */
        private val WEB = setOf("http", "https")

        /**
         * Null for anything that is not a web address, which is what stops a `file:` or
         * `ftp:` href out of a feed from being treated as a place a credential could belong
         * to.
         */
        fun of(url: String): OpdsOrigin? = runCatching {
            val uri = URI(url)
            val scheme = uri.scheme?.lowercase() ?: return@runCatching null
            val host = uri.host?.lowercase() ?: return@runCatching null
            if (scheme !in WEB || host.isEmpty()) return@runCatching null
            OpdsOrigin(
                scheme = scheme,
                host = host,
                // The scheme's own default when none is written, so `https://a` and
                // `https://a:443` are one origin rather than two.
                port = if (uri.port != -1) uri.port else if (scheme == "https") 443 else 80,
            )
        }.getOrNull()

        /**
         * Whether an address is one the app will fetch at all.
         *
         * Judged before anything opens a connection. `URL.openConnection()` accepts `file:`,
         * `ftp:` and `jar:` and hands back a connection that is not an `HttpURLConnection` --
         * the unchecked cast then throws `ClassCastException`, which no catch clause in this
         * app matches and which therefore kills the process.
         */
        fun isFetchable(url: String): Boolean =
            runCatching { URI(url).scheme?.lowercase() in WEB }.getOrDefault(false)
    }
}
