package app.storyarc.feature.library

import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsError
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaError
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.CredentialStore

/**
 * Whether a source is actually there.
 *
 * `sources` requires a source's health to be shown. State is never persisted -- it describes
 * a network, and a state read from disk is a claim about the past -- so a catalogue or a
 * server loads as `Connecting` and stays there unless something asks. Nothing did, so every
 * network source a reader added read "Connecting..." for ever, reachable or not.
 */
object SourceHealth {

    /** Which sources this can answer for. A folder answers itself when it is restored. */
    fun canProbe(source: Source): Boolean =
        source.kind == SourceKind.OPDS_CATALOG || source.kind == SourceKind.KAVITA_SERVER

    /**
     * One request, and what it means.
     *
     * Offline is a normal state rather than a failure, so only a refused key is
     * `Unauthorized` -- that is the one a reader has to do something about.
     */
    suspend fun probe(
        source: Source,
        credentials: CredentialStore?,
        pins: CertificatePins,
        now: Long,
        unauthorizedReason: String,
    ): SourceConnectionState {
        KavitaPage.of(source, credentials)?.let { page ->
            return try {
                KavitaClient(page.address).connect()
                SourceConnectionState.Connected
            } catch (error: KavitaError.KeyRejected) {
                SourceConnectionState.Unauthorized(unauthorizedReason)
            } catch (error: Exception) {
                SourceConnectionState.Unreachable(now)
            }
        }

        CataloguePage.of(source, credentials)?.let { page ->
            return try {
                OpdsClient(pins).feed(page.url, page.credential)
                SourceConnectionState.Connected
            } catch (error: OpdsError.Unauthorized) {
                SourceConnectionState.Unauthorized(unauthorizedReason)
            } catch (error: Exception) {
                SourceConnectionState.Unreachable(now)
            }
        }

        // Neither page could be built, so the secret this source needs has gone.
        return SourceConnectionState.Unauthorized(unauthorizedReason)
    }
}
