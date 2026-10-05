package app.storyarc.feature.library

import android.content.Context
import android.util.Log
import app.storyarc.core.catalogue.OpdsError
import app.storyarc.core.model.DownloadFailure
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

private const val TAG = "StoryArcCatalogue"

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

    /**
     * What a catalogue error *is*, as a reason the record can keep.
     *
     * `localization` 15.9 split this in two: deciding which failure happened, which is here,
     * and saying it in words, which is [DownloadFailureWords]. A download's record holds the
     * first and the row draws the second, so a reader who changes language afterwards gets
     * their own words rather than the ones the app spoke on the day it failed.
     */
    fun reason(error: OpdsError): DownloadFailure = when (error) {
        is OpdsError.Unauthorized -> DownloadFailure.Unauthorized
        is OpdsError.Empty -> DownloadFailure.Empty
        is OpdsError.RefusedAddress -> DownloadFailure.RefusedAddress
        is OpdsError.Redirect -> DownloadFailure.Redirect
        is OpdsError.NotAFeed -> when (val received = error.received) {
            is OpdsError.Received.Html -> DownloadFailure.NotAWebPage
            is OpdsError.Received.Unrecognised -> DownloadFailure.NotAFeed(received.contentType)
        }
        is OpdsError.Malformed -> {
            // The parser's own words, which are English and are a developer's. Logged rather
            // than shown, which is why the reader's reason carries no argument.
            Log.w(TAG, "malformed feed: ${error.reason}")
            DownloadFailure.Malformed
        }
        is OpdsError.Http -> DownloadFailure.Http(error.status)
    }

    /** Why a transfer could not reach the server at all, as a reason the record can keep. */
    fun reaching(error: IOException): DownloadFailure = when (error) {
        is UnknownHostException -> DownloadFailure.NoHost
        is SocketTimeoutException -> DownloadFailure.TimedOut
        else -> {
            Log.w(TAG, "catalogue unreachable", error)
            DownloadFailure.Unreachable
        }
    }

    fun describe(context: Context, error: OpdsError): String =
        DownloadFailureWords.sentence(context, reason(error))

    /** A transport failure, said in terms of what the reader can do about it. */
    fun reachability(context: Context, error: IOException): String =
        DownloadFailureWords.sentence(context, reaching(error))
}
