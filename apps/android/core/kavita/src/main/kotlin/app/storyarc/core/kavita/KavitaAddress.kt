package app.storyarc.core.kavita

import java.net.URI

/**
 * Where a Kavita server is and how to prove who you are.
 *
 * `kavita-server` takes "a base URL and a user API key". Both are needed for every request
 * and neither is useful alone, so they travel together. iOS's `KavitaAddress` is the same
 * pair with the same two ways of arriving at it.
 */
data class KavitaAddress(
    /** The server's root -- `https://kavita.example`, with no `/api` and no trailing slash. */
    val base: String,
    /** The reader's own API key, from Kavita's user settings. */
    val apiKey: String,
) {
    /** One of Kavita's endpoints, relative to the base. */
    fun endpoint(path: String, query: Map<String, String> = emptyMap()): String {
        val parameters = if (query.isEmpty()) {
            ""
        } else {
            "?" + query.entries.joinToString("&") { (name, value) ->
                "$name=" + java.net.URLEncoder.encode(value, "UTF-8")
            }
        }
        return "$base/api/$path$parameters"
    }

    /**
     * Where one chapter's bytes come from.
     *
     * Named on its own because a download record has to remember where it came from --
     * `offline-downloads` retries from it without re-browsing. It is safe to write down:
     * Kavita takes the key as a bearer header on this route, so the URL is a path and a
     * chapter number and carries no secret. An OPDS acquisition link, which can embed one, is
     * the reason that distinction is worth making out loud.
     */
    fun chapterUrl(chapterId: Int): String =
        endpoint("Download/chapter", mapOf("chapterId" to chapterId.toString()))

    /**
     * The server, and the fact that a key is held -- never the key.
     *
     * A `data class` writes its own `toString`, and this one's second field is the reader's
     * API key, so every interpolation of an address into a message, a diagnostic or a crash
     * breadcrumb would have carried the secret out of memory. `AGENTS.md` non-negotiable 4
     * says redact before any string leaves memory, and a default nobody wrote is exactly the
     * kind that leaks. iOS's `description` says the same thing.
     */
    override fun toString(): String =
        "KavitaAddress(base=$base, apiKey=${if (apiKey.isEmpty()) "none" else "redacted"})"

    companion object {
        /**
         * Reads an address out of whatever the reader pasted.
         *
         * `kavita-server`: when a reader pastes "a Kavita OPDS URL that embeds the API key",
         * the app "extracts the base URL and key and configures a native Kavita source
         * rather than a generic OPDS source". Kavita's OPDS URL is
         * `https://host/api/opds/<key>`, so the paste a reader is most likely to have to
         * hand already contains everything.
         *
         * Null for a URL that is not one of Kavita's, which is what lets the caller fall
         * back to asking for the two pieces separately.
         */
        fun fromOpds(pasted: String): KavitaAddress? {
            val trimmed = pasted.trim()
            if (trimmed.isEmpty()) return null
            val completed = if (trimmed.contains("://")) trimmed else "https://$trimmed"
            val uri = runCatching { URI(completed) }.getOrNull() ?: return null
            if (uri.host.isNullOrEmpty()) return null

            // Found by looking for the marker rather than by counting components: a reverse
            // proxy can put Kavita at any depth, and dropping the prefix would send every
            // later request to a path the proxy does not serve.
            val parts = uri.path.orEmpty().split("/").filter { it.isNotEmpty() }
            val opds = parts.indexOf("opds")
            if (opds <= 0 || parts[opds - 1] != "api" || opds + 1 >= parts.size) return null
            val key = parts[opds + 1]
            if (key.isEmpty()) return null

            val prefix = parts.take(opds - 1)
            val port = if (uri.port > 0) ":${uri.port}" else ""
            val path = if (prefix.isEmpty()) "" else "/" + prefix.joinToString("/")
            return KavitaAddress("${uri.scheme}://${uri.host}$port$path", key)
        }

        /**
         * An address from a base URL a reader typed and a key they pasted separately.
         *
         * Trailing slashes and a pasted `/api` are removed rather than refused: both are
         * things a reader copies out of a browser bar, and neither is a mistake worth an
         * error message.
         */
        fun from(base: String, apiKey: String): KavitaAddress? {
            val key = apiKey.trim()
            val typed = base.trim()
            if (key.isEmpty() || typed.isEmpty()) return null

            val completed = if (typed.contains("://")) typed else "https://$typed"
            val uri = runCatching { URI(completed) }.getOrNull() ?: return null
            if (uri.host.isNullOrEmpty()) return null

            var path = uri.path.orEmpty().trimEnd('/')
            if (path.endsWith("/api")) path = path.dropLast(4)
            val port = if (uri.port > 0) ":${uri.port}" else ""
            return KavitaAddress("${uri.scheme}://${uri.host}$port$path", key)
        }
    }
}
