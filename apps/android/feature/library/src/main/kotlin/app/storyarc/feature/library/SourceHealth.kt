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
import app.storyarc.core.smb.SmbClient
import app.storyarc.core.smb.SmbError

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
        source.kind == SourceKind.OPDS_CATALOG ||
            source.kind == SourceKind.KAVITA_SERVER ||
            source.kind == SourceKind.NETWORK_SHARE

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
        encryptionReason: String,
    ): SourceConnectionState {
        SmbPage.of(source, credentials)?.let { page ->
            return try {
                SmbClient(page.address).use { it.connect() }
                SourceConnectionState.Connected
            } catch (refusal: SmbError) {
                SmbSourceState.of(refusal, now, unauthorizedReason, encryptionReason)
            } catch (error: Exception) {
                SourceConnectionState.Unreachable(now)
            }
        }

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

/**
 * What a share's refusal means for the source that named it.
 *
 * `network-share` asks the app to "report the specific failure". The add-a-share sheet does
 * that through [SmbConnection]; the health probe behind a share already saved sent every
 * refusal but a rejected password to `Unreachable`, so a share that demands SMB 3 encryption
 * read "No answer since ...". The server answered. It refused, for a reason the reader can act
 * on, and `sources` re-asks an unreachable source every 5 s rising to every 5 minutes -- so the
 * wrong state also asked a share that can never say yes, for as long as the library was on
 * screen.
 *
 * Pure, and its own type, for the reason [ShelfRefresh] is: a decision written inside a `catch`
 * around a network call is a decision nothing can assert. It takes its two sentences as
 * parameters because an object has no `Context` to read them from; iOS's `SmbSourceState` reads
 * its own bundle and holds the same table.
 */
object SmbSourceState {
    /**
     * The state a source takes when its share refuses.
     *
     * Only a refusal the reader can do something about is `Unauthorized`. An SMB 1 server and
     * a share that is simply not there are both offline, which is a normal state and grey.
     */
    fun of(
        error: SmbError,
        now: Long,
        unauthorizedReason: String,
        encryptionReason: String,
    ): SourceConnectionState = when (error) {
        is SmbError.AuthenticationRejected -> SourceConnectionState.Unauthorized(unauthorizedReason)
        is SmbError.EncryptionRequired -> SourceConnectionState.Unauthorized(encryptionReason)
        is SmbError.HostUnreachable,
        is SmbError.ShareNotFound,
        is SmbError.ProtocolUnsupported,
        is SmbError.Unexpected,
        -> SourceConnectionState.Unreachable(now)
    }
}
