package app.storyarc.feature.library

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.catalogue.OpdsDocument
import app.storyarc.core.catalogue.OpdsError
import app.storyarc.core.catalogue.OpdsRefusal
import app.storyarc.core.catalogue.UntrustedCertificate
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.CertificatePinStore
import app.storyarc.core.persistence.CredentialStore
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Adding a catalogue, from a URL to a saved source.
 *
 * `opds-catalog`'s first scenario: the app "fetches the root feed, detects the OPDS version,
 * and shows the catalogue title as confirmation before saving". Confirmation before saving
 * is the point -- a reader who mistyped a host should find out here, not by browsing an
 * empty library later.
 *
 * Every branch the spec names is a step, so none of them can be reached by accident: a 401
 * asks for credentials, an untrusted certificate shows its fingerprint, and anything that is
 * not a feed says what it was. iOS's `CatalogueConnection` is the same state machine.
 */
class CatalogueConnection(
    private val context: Context,
    private val pins: CertificatePins,
    private val pinStore: CertificatePinStore?,
    private val credentials: CredentialStore?,
) : ViewModel() {

    /** Where the reader is in the flow. */
    sealed interface Step {
        /** Waiting for a URL. */
        data object Entering : Step

        /** A request is out. */
        data object Connecting : Step

        /** The server asked who is calling. */
        data class AskingCredentials(val scheme: OpdsError.AuthenticationScheme?) : Step

        /** The server's certificate is not one the system vouches for. */
        data class Untrusted(val certificate: UntrustedCertificate) : Step

        /** The root feed came back, and this is what it calls itself. */
        data class Confirmed(val title: String) : Step

        /** Something else happened, said plainly. */
        data class Failed(val message: String) : Step
    }

    private val _step = MutableStateFlow<Step>(Step.Entering)
    val step: StateFlow<Step> = _step.asStateFlow()

    /** The address, as typed. Completed only when a request is made. */
    val address = MutableStateFlow("")
    val user = MutableStateFlow("")
    val password = MutableStateFlow("")
    val token = MutableStateFlow("")

    private val client = OpdsClient(pins)

    /**
     * The URL that answered, kept so saving uses the address that worked rather than the one
     * that was typed -- a host that redirects to a path is common, and saving the typed form
     * means every later request pays for the redirect again.
     */
    private var resolved: String? = null

    /** The credential that worked, held only until the source is saved. */
    private var accepted: OpdsCredential? = null

    /** Fetches the root feed and reports what came back. */
    fun connect() {
        val url = OpdsDocument.address(address.value)
        if (url == null) {
            _step.value = Step.Failed(context.getString(R.string.catalogue_error_not_a_url))
            return
        }
        viewModelScope.launch { attempt(url, accepted) }
    }

    /** Tries again with what the reader just typed into the credential prompt. */
    fun submitCredentials() {
        val current = _step.value
        if (current !is Step.AskingCredentials) return
        val url = resolved ?: OpdsDocument.address(address.value) ?: return
        // Basic when the server said Basic, and Basic when it said nothing: a server with no
        // challenge that still refuses is almost always Basic, and the reader can see which
        // fields they were given.
        val credential = if (current.scheme == OpdsError.AuthenticationScheme.BEARER) {
            OpdsCredential.Bearer(token.value)
        } else {
            OpdsCredential.Basic(user.value, password.value)
        }
        viewModelScope.launch { attempt(url, credential) }
    }

    /**
     * Accepts one certificate, then tries again.
     *
     * Only reachable from [Step.Untrusted], which is the step that shows the fingerprint.
     * `opds-catalog` requires the warning before the offer, and the step is what makes that
     * ordering structural rather than remembered.
     */
    fun trustCertificate() {
        val current = _step.value
        if (current !is Step.Untrusted) return
        val url = resolved ?: OpdsDocument.address(address.value) ?: return
        pins.pin(current.certificate.fingerprint, current.certificate.host)
        // Written now rather than when the source is saved. A reader who accepts a
        // certificate and then abandons the flow has still made that decision, and asking
        // again next time teaches them to tap through the warning.
        pinStore?.save(pins.all)
        viewModelScope.launch { attempt(url, accepted) }
    }

    /**
     * The source to save, once the catalogue has confirmed its own name.
     *
     * Null before then, which is what stops an unconfirmed catalogue from being saved. The
     * secret goes to the platform secure store and its reference to the registry --
     * `sources` forbids the secret itself reaching the registry.
     */
    fun source(): Source? {
        val confirmed = _step.value as? Step.Confirmed ?: return null
        val url = resolved ?: return null

        val id = UUID.randomUUID()
        var reference: String? = null
        val secret = accepted
        if (secret != null) {
            // Null when the secret cannot be stored, and the step says so. A catalogue whose
            // sign-in was accepted and then dropped is a row that fails on the next launch
            // with nothing to explain why.
            val stored = CredentialStore.reference(id)
            if (credentials == null || !credentials.save(secret.stored, stored)) {
                _step.value = Step.Failed(
                    context.getString(R.string.catalogue_error_secret_not_stored),
                )
                return null
            }
            reference = stored
        }

        return Source(
            id = id,
            displayName = confirmed.title,
            kind = SourceKind.OPDS_CATALOG,
            state = SourceConnectionState.Connected,
            credentialReference = reference,
            locator = url,
        )
    }

    /** Puts the flow back to the start, for a sheet that is opened again. */
    fun reset() {
        _step.value = Step.Entering
    }

    private suspend fun attempt(url: String, credential: OpdsCredential?) {
        _step.value = Step.Connecting
        try {
            val feed = client.feed(url, credential)
            resolved = url
            accepted = credential
            // A feed with no title still connected. Named by its host rather than left
            // blank: `sources` requires the name to appear "everywhere the source is
            // referenced", and a blank one reads as a missing word.
            _step.value = Step.Confirmed(
                feed.title.ifEmpty { runCatching { java.net.URI(url).host }.getOrNull() ?: url },
            )
        } catch (refusal: OpdsRefusal.Untrusted) {
            resolved = url
            _step.value = Step.Untrusted(refusal.certificate)
        } catch (unauthorized: OpdsError.Unauthorized) {
            resolved = url
            _step.value = Step.AskingCredentials(unauthorized.scheme)
        } catch (error: OpdsError) {
            resolved = url
            _step.value = Step.Failed(CatalogueMessages.describe(context, error))
        } catch (error: java.io.IOException) {
            _step.value = Step.Failed(CatalogueMessages.reachability(context, error))
        }
    }
}
