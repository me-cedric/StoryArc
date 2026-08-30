package app.storyarc.feature.library

import android.content.Context
import app.storyarc.core.kavita.KavitaError

/**
 * Why a Kavita server did not answer, in the reader's words rather than the exception's.
 *
 * **`kavita-server`'s revoked-key scenario asks for "an explanation and an action".** The
 * marking was right on both platforms -- a refused key puts the source in `Unauthorized`,
 * which `SourceDiagnosis` answers with the `RECONNECT` action, and that re-opens the sheet the
 * server was added through with everything but the secret filled in. What was missing was the
 * sentence, and on this platform there was not even a failed one: the browser swallowed every
 * error into an empty list, so a reader whose key had been revoked saw a server with no
 * libraries in it and nothing at all to say why.
 *
 * The explanation names the action rather than describing the failure twice, because a reader
 * who has just been told what is wrong wants to know where to fix it. iOS's `KavitaMessage`
 * says the same four things.
 */
internal object KavitaMessage {
    fun of(context: Context, error: Throwable, source: String): String = when (error) {
        // The key the keystore still holds is one the server no longer accepts. Not the same
        // as a missing key, and not the same as a server that is down.
        KavitaError.KeyRejected ->
            context.getString(R.string.source_unauthorized_refused_body, source)
        is KavitaError.ServerTooOld ->
            context.getString(
                R.string.kavita_error_too_old,
                error.found.toString(),
                error.required.toString(),
            )
        KavitaError.BadAddress, KavitaError.UnexpectedResponse ->
            context.getString(R.string.kavita_error_not_kavita)
        // Any other status is the server being unwell rather than the reader being wrong, and
        // `sources` makes that a grey state with an offer to try again.
        else -> context.getString(R.string.source_offline_body, source)
    }
}
