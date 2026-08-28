package app.storyarc.core.smb

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
)
