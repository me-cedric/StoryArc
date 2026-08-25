package app.storyarc.core.model

/**
 * Removes from a diagnostic anything a reader would not knowingly publish.
 *
 * `settings-and-about` requires the diagnostic export to be shown before sharing
 * "with every credential, token and server hostname redacted", and that the redaction
 * is "a tested function, not a regex written at the call site". This is that function.
 * iOS's `DiagnosticRedaction` applies the same five rules in the same order.
 *
 * It over-redacts deliberately. A diagnostic missing a hostname is still useful; a
 * diagnostic carrying a token is a leak the reader cannot take back.
 *
 * Redaction is the second line of defence, not the first. The first is that
 * `DiagnosticReport` puts no free text in the report at all — a source is reported by
 * kind and state rather than by the name the reader gave it, because a name they chose
 * is where a hostname would be. This function guards the one place free text is
 * unavoidable: file paths.
 */
object DiagnosticRedaction {

    /**
     * What replaces a removed value.
     *
     * Named rather than blanked, so a reader reading their own report can see that
     * something was removed and what kind of thing it was. A blank looks like a bug in
     * the export.
     */
    const val CREDENTIAL = "[redacted]"
    const val HOST = "[host]"
    const val TOKEN = "[token]"
    const val HOME = "~"

    /**
     * Rule 1 — the whole authority of a URL, in one span.
     *
     * Taken as one span rather than as user, host and port separately: split rules
     * leave the parts they do not claim behind, and the part left behind is the
     * password.
     */
    private val urlAuthority = Regex("""([a-zA-Z][a-zA-Z0-9+.\-]*://)[^/\s?#]*""")

    /** Rule 2 — a bare IPv4 address, which needs no scheme to identify a server. */
    private val bareAddress = Regex("""\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b""")

    /** Rule 3 — a value introduced by a word that means "secret". */
    private val keyedCredential = Regex(
        """\b(token|password|passwd|secret|key|apikey|api_key|auth|authorization|bearer)\b[\s=:]+\S+""",
        RegexOption.IGNORE_CASE,
    )

    /**
     * Rule 4 — a long unbroken run of token-shaped characters.
     *
     * The backstop for a credential that arrives with no key naming it. Thirty-two
     * characters is above anything a word or a version string reaches and below every
     * API key format in use.
     */
    private val opaqueRun = Regex("""\b[A-Za-z0-9+/_\-]{32,}\b""")

    /** Rule 5 — the home directory, which carries the reader's own name. */
    private val homeDirectory = Regex("""/(?:Users|home)/[^/\s]+""")

    /** Applies every rule, in order. Order matters and is asserted by the tests. */
    fun redact(text: String): String = text
        .replace(urlAuthority) { it.groupValues[1] + HOST }
        .replace(bareAddress) { HOST }
        .replace(keyedCredential) { "${it.groupValues[1]}=$CREDENTIAL" }
        .replace(opaqueRun) { TOKEN }
        .replace(homeDirectory) { HOME }
}
