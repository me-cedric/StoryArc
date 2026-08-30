package app.storyarc.feature.library

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaError
import app.storyarc.core.kavita.KavitaIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.CredentialStore
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Adding a Kavita server, from a URL and a key to a saved source.
 *
 * `kavita-server`: the app "authenticates, confirms the server version and the account name,
 * and saves the source". iOS's `KavitaConnection` is the same state machine.
 */
class KavitaConnection(
    private val context: Context,
    private val credentials: CredentialStore?,
) : ViewModel() {

    sealed interface Step {
        data object Entering : Step
        data object Connecting : Step
        data class Confirmed(val identity: KavitaIdentity) : Step
        data class Failed(val message: String) : Step
    }

    private val _step = MutableStateFlow<Step>(Step.Entering)
    val step: StateFlow<Step> = _step.asStateFlow()

    val address = MutableStateFlow("")
    val apiKey = MutableStateFlow("")

    /**
     * The source this connection is putting back, when it is re-authorising one.
     *
     * `sources` requires "a single action to re-enter credentials, pre-filled with everything
     * except the secret". Holding the source rather than only its address is what makes the
     * result a *replacement*: the same identifier keeps the source's place in the order, its
     * downloads and its reading positions, where removing and re-adding loses all three.
     */
    var replacing: Source? = null
        private set

    private var resolved: KavitaAddress? = null

    /**
     * Seeds the sheet from a source whose key was refused.
     *
     * The address comes back, the key does not. A key the server has just rejected is not a
     * starting point, and showing dots where one used to be would invite the reader to press
     * Connect on the credential that failed.
     */
    fun prefill(source: Source) {
        replacing = source
        address.value = source.locator.orEmpty()
        apiKey.value = ""
        _step.value = Step.Entering
    }

    /**
     * Whether the address the reader pasted already carries a key.
     *
     * Read by the sheet, which hides the key field when it does: asking for something the
     * reader has already given is how a form makes someone feel they typed it wrong.
     *
     * Takes the text rather than reading `address.value`. A flow's `value` is a plain field,
     * so Compose never learns the answer depends on it, and the key field stayed on screen
     * after a pasted OPDS URL had already answered the question.
     */
    fun carriesKey(text: String): Boolean = KavitaAddress.fromOpds(text) != null

    fun connect() {
        // A pasted OPDS URL wins, because it is unambiguous: it names the server and the key
        // together, and a key typed beside it could only disagree.
        val target = KavitaAddress.fromOpds(address.value)
            ?: KavitaAddress.from(address.value, apiKey.value)
        if (target == null) {
            _step.value = Step.Failed(context.getString(R.string.kavita_error_not_an_address))
            return
        }

        _step.value = Step.Connecting
        viewModelScope.launch {
            try {
                val identity = KavitaClient(target).connect()
                resolved = target
                _step.value = Step.Confirmed(identity)
            } catch (error: KavitaError) {
                _step.value = Step.Failed(describe(error))
            } catch (error: IOException) {
                _step.value = Step.Failed(CatalogueMessages.reachability(context, error))
            }
        }
    }

    /**
     * The source to save, once the server has confirmed who it is.
     *
     * Null when the key cannot be stored, and the step says so. A Kavita source without its
     * key is a row that fails on the next launch with nothing to explain why -- saving one
     * would be the app quietly forgetting a password the reader watched it accept.
     */
    fun source(): Source? {
        val confirmed = _step.value as? Step.Confirmed ?: return null
        val target = resolved ?: return null

        return kavitaSource(target, confirmed.identity, credentials, replacing) ?: run {
            _step.value = Step.Failed(context.getString(R.string.kavita_error_key_not_stored))
            null
        }
    }

    fun reset() {
        _step.value = Step.Entering
    }

    private fun describe(error: KavitaError): String = describeKavita(context, error)
}

/**
 * A confirmed Kavita server, written down as a source.
 *
 * Shared by the Kavita sheet and by the catalogue sheet — which diverts a pasted Kavita OPDS
 * URL here rather than letting the key that URL carries become an OPDS locator. One function
 * rather than two, because the two would drift and only one of them would be the one that
 * keeps the key out of preferences.
 *
 * Null when the key cannot be stored. A Kavita source without its key is a row that fails on
 * the next launch with nothing to explain why, so the caller says so instead of saving one.
 */
internal fun kavitaSource(
    address: KavitaAddress,
    identity: KavitaIdentity,
    credentials: CredentialStore?,
    /**
     * The source being re-authorised, when there is one. Its identifier and its credential
     * reference are reused, so the new key lands under the name the registry already holds
     * and the source keeps everything filed under that identifier.
     */
    replacing: Source? = null,
): Source? {
    val id = replacing?.id ?: UUID.randomUUID()
    val reference = replacing?.credentialReference ?: CredentialStore.reference(id)
    if (credentials == null || !credentials.save(address.apiKey, reference)) return null

    return Source(
        id = id,
        // The account name, not the host. A reader with two accounts on one server needs to
        // tell them apart, and the host is the same for both.
        displayName = "${identity.username} · ${hostOf(address.base)}",
        kind = SourceKind.KAVITA_SERVER,
        state = SourceConnectionState.Connected,
        credentialReference = reference,
        // The base, which is the address with the key taken out of it. `sources` forbids a
        // secret reaching preferences, and the registry is preferences.
        locator = address.base,
    )
}

internal fun hostOf(base: String): String =
    runCatching { java.net.URI(base).host }.getOrNull() ?: "Kavita"

/**
 * What went wrong, said plainly.
 *
 * Top-level rather than a method, because the catalogue sheet reports the same errors: a
 * Kavita OPDS URL pasted there is answered by Kavita.
 */
internal fun describeKavita(context: Context, error: KavitaError): String = when (error) {
    is KavitaError.ServerTooOld -> context.getString(
        R.string.kavita_error_too_old,
        error.found.toString(),
        error.required.toString(),
    )
    is KavitaError.KeyRejected -> context.getString(R.string.kavita_error_key_rejected)
    is KavitaError.BadAddress -> context.getString(R.string.kavita_error_not_an_address)
    is KavitaError.UnexpectedResponse -> context.getString(R.string.kavita_error_not_kavita)
    is KavitaError.Http -> context.getString(R.string.catalogue_error_http, error.status)
}

/** What is needed to open a saved Kavita source. */
data class KavitaPage(val id: String, val title: String, val address: KavitaAddress) {
    companion object {
        /**
         * Null when the source is not a Kavita server, has no address, or has lost its key --
         * the last of which is what `unauthorized` means and needs the reader to fix.
         */
        fun of(source: Source, credentials: CredentialStore?): KavitaPage? {
            if (source.kind != SourceKind.KAVITA_SERVER) return null
            val base = source.locator ?: return null
            val reference = source.credentialReference ?: return null
            val key = credentials?.secret(reference) ?: return null
            return KavitaPage(
                source.id.toString(),
                source.displayName,
                KavitaAddress(base, key),
            )
        }
    }
}
