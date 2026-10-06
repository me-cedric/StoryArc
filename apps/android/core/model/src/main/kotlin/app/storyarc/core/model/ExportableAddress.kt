package app.storyarc.core.model

/**
 * A source's address with everything that could unlock it taken out, and nothing else.
 *
 * `library-portability` / *A server in the export*: "its address, its name, its username and
 * its settings travel, and its secret does not". A [Source.locator] is the address, and an
 * address is one of the few places in this app where a secret can sit in plain sight — a
 * share mounted as `smb://reader:hunter2@nas.local/comics`, a catalogue subscribed to as
 * `https://opds.example/feed?apikey=...`. `AGENTS.md` non-negotiable 4 names backups, and an
 * export is a backup.
 *
 * **Deliberately not [DiagnosticRedaction].** That function removes the hostname too, because
 * a diagnostic is a file the reader sends to somebody else and a hostname is something they
 * would not knowingly publish. An export is a file the reader carries to their own next
 * device, and a source whose hostname has been removed is a source that cannot be reached —
 * the export's whole purpose. The two over-redact and under-redact in opposite directions on
 * purpose, and the spec says so in as many words.
 *
 * iOS's `ExportableAddress` applies the same two rules in the same order.
 */
object ExportableAddress {

    /**
     * The address, with the password out of its userinfo and any secret-named query parameter
     * dropped.
     *
     * A locator this app does not recognise as a URL — a folder tree URI, a bookmark name —
     * is returned as it stands. There is nowhere in a path for a secret to hide, and mangling
     * one would lose the source.
     */
    fun withoutSecret(locator: String): String = withoutSecretQueryItems(withoutPassword(locator))

    /**
     * `smb://reader:hunter2@nas.local/comics` becomes `smb://reader@nas.local/comics`.
     *
     * The user survives because `library-portability` says the username travels; a reader
     * signing in again on the new device should have to supply the secret and not also
     * remember which account it was.
     */
    private fun withoutPassword(locator: String): String =
        USER_INFO.replace(locator) { match ->
            val user = match.groupValues[2].substringBefore(':')
            "${match.groupValues[1]}$user@"
        }

    /**
     * Drops `?apikey=...`, `?token=...` and their kin, and keeps every other parameter.
     *
     * The same vocabulary [DiagnosticRedaction] uses for its keyed-credential rule, because a
     * word that means "secret" means it in both files. Dropped rather than blanked: a
     * parameter whose value is `[redacted]` would be sent to the server verbatim on the next
     * launch, and a server answering 401 to a literal `[redacted]` is a worse failure to
     * explain than a parameter that is simply not there.
     */
    private fun withoutSecretQueryItems(locator: String): String {
        // The fragment is cut first and filtered by the same rule. A fragment never reaches
        // a server, so it reads as harmless, but it is still text in an exported file -- and
        // `https://host/feed#token=abc` carries the whole token past a filter that only ever
        // looks after a `?`.
        val hash = locator.indexOf('#')
        val beforeHash = if (hash < 0) locator else locator.substring(0, hash)
        val fragment = if (hash < 0) null else keptItems(locator.substring(hash + 1))

        val separator = beforeHash.indexOf('?')
        val address = if (separator < 0) beforeHash else beforeHash.substring(0, separator)
        val query = if (separator < 0) null else keptItems(beforeHash.substring(separator + 1))

        return address +
            query?.let { "?$it" }.orEmpty() +
            fragment?.let { "#$it" }.orEmpty()
    }

    /** The `a=1&b=2` items that name no secret, or null where none is left. */
    private fun keptItems(items: String): String? = items
        .split('&')
        .filterNot { it.substringBefore('=').lowercase() in SECRET_NAMES }
        .takeIf { it.isNotEmpty() }
        ?.joinToString("&")

    private val USER_INFO = Regex("([a-zA-Z][a-zA-Z0-9+.\\-]*://)([^/\\s?#@]*)@")

    /**
     * The parameter names that introduce a secret.
     *
     * A list rather than a shape test, because a parameter's *value* is opaque by definition
     * and only its name says what it is. Kept in step with iOS's `ExportableAddress`, which
     * holds the same words.
     */
    private val SECRET_NAMES = setOf(
        "token", "password", "passwd", "pwd", "secret", "key", "apikey", "api_key", "api-key",
        "x-api-key", "auth", "authorization", "bearer", "accesstoken", "access_token",
        "refresh_token", "refreshtoken", "session", "sessionid", "session_id", "sid",
        "credential", "credentials", "signature", "sig",
    )
}
