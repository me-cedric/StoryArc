package app.storyarc.feature.library

import android.content.Context
import app.storyarc.core.catalogue.OpdsError
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * What a reader is told when a catalogue does not answer the way it should.
 *
 * One place, because the same failure can arrive while adding a catalogue and while browsing
 * it, and two sets of words for one condition is how a bug report ends up describing
 * something nobody can find.
 *
 * `opds-catalog` requires the app to say "what it received -- an HTML page, a redirect, a
 * 404 -- instead of reporting a generic failure", so each case has its own sentence.
 */
internal object CatalogueMessages {

    fun describe(context: Context, error: OpdsError): String = when (error) {
        is OpdsError.Unauthorized -> context.getString(R.string.catalogue_error_unauthorized)
        is OpdsError.Empty -> context.getString(R.string.catalogue_error_empty)
        is OpdsError.NotAFeed -> when (val received = error.received) {
            is OpdsError.Received.Html -> context.getString(R.string.catalogue_error_html)
            is OpdsError.Received.Unrecognised -> context.getString(
                R.string.catalogue_error_not_a_feed,
                received.contentType ?: context.getString(R.string.catalogue_error_unknown_type),
            )
        }
        is OpdsError.Malformed -> context.getString(R.string.catalogue_error_malformed, error.reason)
        is OpdsError.Http -> context.getString(R.string.catalogue_error_http, error.status)
    }

    /** A transport failure, said in terms of what the reader can do about it. */
    fun reachability(context: Context, error: IOException): String = when (error) {
        is UnknownHostException -> context.getString(R.string.catalogue_error_no_host)
        is SocketTimeoutException -> context.getString(R.string.catalogue_error_timed_out)
        else -> error.message ?: context.getString(R.string.catalogue_error_unreachable)
    }
}
