package app.storyarc.feature.library

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.smb.SmbAddress
import app.storyarc.core.smb.SmbClient
import app.storyarc.core.smb.SmbEntry
import app.storyarc.core.smb.SmbError
import app.storyarc.core.smb.SmbIdentity
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Adding a share, from a host and a password to a saved source.
 *
 * `network-share` validates "before saving" and reports "the specific failure", then lets a
 * reader "browse the share's directory tree and pick the folder to use as the library root".
 * Those are two steps rather than one screen, and this is the state machine between them.
 */
class SmbConnection(
    private val context: Context,
    private val credentials: CredentialStore?,
) : ViewModel() {

    sealed interface Step {
        data object Entering : Step

        data object Connecting : Step

        /** Connected. The reader is now choosing which folder to read. */
        data class Browsing(
            val identity: SmbIdentity,
            val path: String,
            val entries: List<SmbEntry>,
        ) : Step

        data class Failed(val message: String) : Step
    }

    private val _step = MutableStateFlow<Step>(Step.Entering)
    val step: StateFlow<Step> = _step.asStateFlow()

    val host = MutableStateFlow("")
    val share = MutableStateFlow("")
    val username = MutableStateFlow("")
    val password = MutableStateFlow("")

    private var resolved: SmbAddress? = null

    /** Whether there is enough typed in to try. */
    fun isReady(): Boolean = host.value.isNotBlank() && share.value.isNotBlank()

    /**
     * Connects and lists the share's root, which is the first thing a reader has to choose
     * from.
     *
     * A pasted `smb://host/share/path` or `\\host\share\path` in the host field is read
     * whole, because that is the form a reader is most likely to have to hand.
     */
    fun connect() {
        val pasted = SmbAddress.parse(host.value)
        val target = when {
            pasted != null && share.value.isBlank() -> pasted.copy(
                username = username.value.ifBlank { null },
                password = password.value.ifBlank { null },
            )
            else -> {
                // A host may carry a port. Most readers never type one, but a NAS behind a
                // forwarded port has no other way to say so.
                val typed = host.value.trim().removePrefix("smb://").trim('/', '\\')
                val parts = typed.split(':')
                SmbAddress(
                    host = parts[0],
                    share = share.value.trim().trim('/', '\\'),
                    username = username.value.ifBlank { null },
                    password = password.value.ifBlank { null },
                    port = parts.getOrNull(1)?.toIntOrNull() ?: SmbAddress.DEFAULT_PORT,
                )
            }
        }
        if (target.host.isBlank() || target.share.isBlank()) {
            _step.value = Step.Failed(context.getString(R.string.smb_error_not_an_address))
            return
        }

        _step.value = Step.Connecting
        // On IO from the first line: jcifs resolves names while it builds a client, and
        // doing that on the main thread is an ANR rather than a slow screen.
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val client = SmbClient(target)
                val identity = client.connect()
                resolved = target
                _step.value = Step.Browsing(identity, "", client.list(""))
            } catch (error: SmbError) {
                _step.value = Step.Failed(describe(error))
            }
        }
    }

    /** Opens a folder inside the share, so the reader can go on choosing. */
    fun enter(path: String) {
        val target = resolved ?: return
        val current = _step.value as? Step.Browsing ?: return
        viewModelScope.launch(Dispatchers.IO) {
            val entries = runCatching { SmbClient(target).list(path) }.getOrNull()
            _step.value = entries?.let { current.copy(path = path, entries = it) } ?: current
        }
    }

    /** The folder above the one being shown, or null at the share's root. */
    fun parentOf(path: String): String? =
        path.takeIf { it.isNotEmpty() }?.substringBeforeLast('/', "")

    /**
     * The source to save, rooted at the folder the reader chose.
     *
     * Null when the password cannot be stored, and the step says so. A share whose password
     * is gone is a row that fails on the next launch with nothing to explain why.
     */
    fun source(): Source? {
        val target = resolved ?: return null
        val current = _step.value as? Step.Browsing ?: return null
        val rooted = target.copy(path = current.path)

        val id = UUID.randomUUID()
        var reference: String? = null
        if (!rooted.isGuest) {
            val key = CredentialStore.reference(id)
            if (credentials == null || !credentials.save(rooted.password.orEmpty(), key)) {
                _step.value = Step.Failed(context.getString(R.string.smb_error_key_not_stored))
                return null
            }
            reference = key
        }

        return Source(
            id = id,
            displayName = rooted.displayName,
            kind = SourceKind.NETWORK_SHARE,
            state = SourceConnectionState.Connected,
            credentialReference = reference,
            locator = SmbLocator.of(rooted),
        )
    }

    fun reset() {
        _step.value = Step.Entering
    }

    private fun describe(error: SmbError): String = context.getString(
        when (error) {
            is SmbError.HostUnreachable -> R.string.smb_error_host_unreachable
            is SmbError.ShareNotFound -> R.string.smb_error_share_not_found
            is SmbError.AuthenticationRejected -> R.string.smb_error_authentication
            is SmbError.ProtocolUnsupported -> R.string.smb_error_smb1
            is SmbError.Unexpected -> R.string.smb_error_unexpected
        },
    )
}

/**
 * A share written down, and read back.
 *
 * The registry stores one string per source, so the host, share, path and user name travel
 * as a URL. The password never does -- that is what the credential store is for.
 */
object SmbLocator {
    fun of(address: SmbAddress): String {
        val user = address.username?.takeIf { it.isNotEmpty() }?.let { "$it@" } ?: ""
        val port = if (address.port == SmbAddress.DEFAULT_PORT) "" else ":${address.port}"
        val path = address.path.trim('/').let { if (it.isEmpty()) "" else "/$it" }
        return "smb://$user${address.host}$port/${address.share}$path"
    }

    fun parse(locator: String, password: String?): SmbAddress? {
        val body = locator.removePrefix("smb://")
        val user = body.substringBefore('@', "").takeIf { body.contains('@') }
        val rest = if (user != null) body.substringAfter('@') else body
        val parsed = SmbAddress.parse(rest) ?: return null
        return parsed.copy(username = user, password = password)
    }
}

/** What is needed to open a saved share. */
data class SmbPage(val id: String, val title: String, val address: SmbAddress) {
    companion object {
        /** Null when the source is not a share, has no address, or has lost its password. */
        fun of(source: Source, credentials: CredentialStore?): SmbPage? {
            if (source.kind != SourceKind.NETWORK_SHARE) return null
            val locator = source.locator ?: return null
            val password = source.credentialReference?.let { credentials?.secret(it) }
            if (source.credentialReference != null && password == null) return null
            val address = SmbLocator.parse(locator, password) ?: return null
            return SmbPage(source.id.toString(), source.displayName, address)
        }
    }
}
