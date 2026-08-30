package app.storyarc.core.smb

import java.io.File

/**
 * Where a share is, and who is asking.
 *
 * `network-share` takes "a host, share name, optional path, and either guest access or
 * username and password". All four travel together because none of them is useful alone.
 */
data class SmbAddress(
    val host: String,
    val share: String,
    /** Inside the share. Empty means the share's own root. */
    val path: String = "",
    val username: String? = null,
    val password: String? = null,
    /** Non-standard only for a test server; 445 is the port SMB actually uses. */
    val port: Int = DEFAULT_PORT,
) {
    /** Whether this connects without a name, which some shares allow. */
    val isGuest: Boolean get() = username.isNullOrEmpty()

    /** What to show a reader who is looking at a list of sources. */
    val displayName: String get() = "$host/$share"

    /** A `smb://` URL for jcifs, with the path it was given. */
    fun url(inside: String = path): String {
        val authority = if (port == DEFAULT_PORT) host else "$host:$port"
        val trimmed = inside.trim('/')
        val suffix = if (trimmed.isEmpty()) "" else "$trimmed/"
        return "smb://$authority/$share/$suffix"
    }

    companion object {
        const val DEFAULT_PORT = 445

        /**
         * Reads an address out of what a reader pasted.
         *
         * Accepts `smb://host/share/path` and the `\\host\share\path` form Windows shows,
         * because those are the two a reader is likely to have to hand.
         */
        fun parse(pasted: String): SmbAddress? {
            val trimmed = pasted.trim().replace('\\', '/').removePrefix("smb://").trim('/')
            if (trimmed.isEmpty()) return null

            val parts = trimmed.split('/').filter { it.isNotEmpty() }
            if (parts.size < 2) return null

            val authority = parts[0].split(':')
            val host = authority[0].takeIf { it.isNotEmpty() } ?: return null
            val port = authority.getOrNull(1)?.toIntOrNull() ?: DEFAULT_PORT
            return SmbAddress(
                host = host,
                share = parts[1],
                path = parts.drop(2).joinToString("/"),
                port = port,
            )
        }
    }
}

/**
 * Why a share could not be reached.
 *
 * `network-share` requires the specific failure rather than a general one: "host
 * unreachable, share not found, authentication rejected, or protocol unsupported". A reader
 * who typed the wrong password and a reader whose NAS is asleep need different sentences.
 */
sealed class SmbError(message: String) : Exception(message) {
    data object HostUnreachable : SmbError("host unreachable") {
        private fun readResolve(): Any = HostUnreachable
    }

    data object ShareNotFound : SmbError("share not found") {
        private fun readResolve(): Any = ShareNotFound
    }

    data object AuthenticationRejected : SmbError("authentication rejected") {
        private fun readResolve(): Any = AuthenticationRejected
    }

    /** An SMB 1 server. Refused rather than accommodated -- see [SmbClient]. */
    data object ProtocolUnsupported : SmbError("SMB 1 is not supported") {
        private fun readResolve(): Any = ProtocolUnsupported
    }

    /**
     * The server insists on SMB 3 transport encryption, which this app cannot do.
     *
     * Its own case because it is its own answer. A reader whose NAS requires encryption is
     * not looking at a network fault or a typo -- there is a setting on their server, and a
     * sentence that says so is worth more than a fifth way of saying "could not connect".
     */
    data object EncryptionRequired : SmbError("the server requires SMB 3 encryption") {
        private fun readResolve(): Any = EncryptionRequired
    }

    data class Unexpected(val detail: String) : SmbError(detail)
}

/** One entry in a share's directory tree. */
data class SmbEntry(
    val name: String,
    /** Relative to the share's root, so it can be handed straight back as a path. */
    val path: String,
    val isDirectory: Boolean,
    val length: Long,
)

/** What a connection turned out to be, once it worked. */
data class SmbIdentity(
    /** The dialect the two ends agreed on, such as `SMB 3.1.1`. */
    val dialect: String,
    /**
     * Whether the transport is encrypted.
     *
     * `network-share` requires the source detail screen to state this, which means it has to
     * be a fact about *this* connection rather than about what the app supports.
     */
    val isEncrypted: Boolean,
    /**
     * Whether this session's messages are signed, as the two ends actually negotiated it.
     *
     * A fact about *this* connection, like [isEncrypted]: the client now asks for signing
     * on every session, but a guest share cannot sign at all, so asking is not the same as
     * getting. Unsigned means an attacker on the same network can rewrite a directory
     * listing or a page read on its way here, and a reader deciding whether to trust a
     * share is entitled to know that before they save it.
     */
    val isSigned: Boolean,
)

/**
 * Where this entry's bytes may be written under [directory], or `null` when the server's
 * name is not usable as a filename.
 *
 * A hostile server picks both the destination and the content. [SmbEntry.name] comes
 * verbatim out of a directory listing, and a name of `../shared_prefs/settings.xml` handed
 * straight to `File(directory, name)` resolves out of the cache directory and into the
 * app's own preferences -- the server then chooses what is written there. Only a decoder
 * that needs a real file (`PdfRenderer`, libarchive) makes the app write anything down, and
 * the server chooses which format it serves, so it chooses whether that happens.
 *
 * The rule is the one `ImageFolderArchive` applies to a publication's own internal paths:
 * keep the last component, and refuse a name that means a directory rather than a file.
 * Refused rather than trimmed, like a download id -- trimming is what invites `....//` and
 * the rest of that family -- and the resolved path is checked back against [directory] as
 * the belt to that brace.
 *
 * Not filtered in [SmbClient.list]: a share may legitimately show a folder called `..` and
 * the browser can display it. The name only becomes dangerous where it becomes a path.
 */
fun SmbEntry.cacheLocation(directory: File): File? {
    // Both separators. `\` is SMB's own, and a rule that knows only `/` is a rule written
    // in the wrong protocol.
    val last = name.split('/', '\\').lastOrNull { it.isNotEmpty() } ?: return null
    // `.`, `..`, and any longer run of dots -- every one of them names a directory.
    if (last.all { it == '.' }) return null
    // Nothing that survived the split can still be a separator, and nothing that reaches a
    // filesystem call may carry a NUL. Checked anyway: this is the last place either could
    // be true.
    if (last.any { it == '/' || it == '\\' || it == '\u0000' }) return null

    val local = File(directory, last)
    if (!local.canonicalPath.startsWith(directory.canonicalPath + File.separator)) return null
    return local
}
