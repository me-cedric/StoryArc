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

    private var resolved: KavitaAddress? = null

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

        val id = UUID.randomUUID()
        val reference = CredentialStore.reference(id)
        if (credentials == null || !credentials.save(target.apiKey, reference)) {
            _step.value = Step.Failed(context.getString(R.string.kavita_error_key_not_stored))
            return null
        }

        return Source(
            id = id,
            // The account name, not the host. A reader with two accounts on one server needs
            // to tell them apart, and the host is the same for both.
            displayName = "${confirmed.identity.username} · ${hostOf(target.base)}",
            kind = SourceKind.KAVITA_SERVER,
            state = SourceConnectionState.Connected,
            credentialReference = reference,
            locator = target.base,
        )
    }

    fun reset() {
        _step.value = Step.Entering
    }

    private fun hostOf(base: String): String =
        runCatching { java.net.URI(base).host }.getOrNull() ?: "Kavita"

    private fun describe(error: KavitaError): String = when (error) {
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
}

/** What is needed to open a saved Kavita source. */
data class KavitaPage(val title: String, val address: KavitaAddress) {
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
            return KavitaPage(source.displayName, KavitaAddress(base, key))
        }
    }
}
