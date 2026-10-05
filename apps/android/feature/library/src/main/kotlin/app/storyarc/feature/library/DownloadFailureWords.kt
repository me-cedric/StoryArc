package app.storyarc.feature.library

import android.content.Context
import app.storyarc.core.model.DownloadFailure

/**
 * A failed download's reason, said in the language the reader has chosen *now*.
 *
 * `localization` 15.9: the sentence used to be composed when the download failed and written
 * into the record, so it kept the language the app spoke that day. Switching the app to French
 * left every failed row in English for ever. The record holds a [DownloadFailure] now, and this
 * is where it becomes words -- at the moment a row is drawn, which is the only moment the
 * chosen language is known.
 *
 * Here rather than in `core:model` because this is where the strings are. The [Context] is the
 * caller's to speak the reader's language with, the same way [CatalogueMessages] takes one: a
 * composable passes `LocalContext.current`, and a service passes
 * `context.speakingReaderLanguage()`.
 *
 * iOS's `DownloadFailureWords` is its twin.
 */
object DownloadFailureWords {
    /**
     * The sentence for whatever the record stored.
     *
     * Takes the stored spelling rather than the value, because every caller has a record and
     * [DownloadFailure.of] is what turns an older build's sentence into
     * [DownloadFailure.Unknown].
     */
    fun sentence(context: Context, stored: String): String = sentence(context, DownloadFailure.of(stored))

    fun sentence(context: Context, failure: DownloadFailure): String = when (failure) {
        is DownloadFailure.UnsupportedFormat ->
            context.getString(R.string.catalogue_acquire_unsupported, failure.format)
        DownloadFailure.Unreadable -> context.getString(R.string.catalogue_acquire_unreadable)
        DownloadFailure.ContentProtected -> context.getString(R.string.catalogue_acquire_protected)
        DownloadFailure.Unauthorized -> context.getString(R.string.catalogue_error_unauthorized)
        DownloadFailure.Empty -> context.getString(R.string.catalogue_error_empty)
        DownloadFailure.RefusedAddress -> context.getString(R.string.catalogue_error_refused_address)
        DownloadFailure.Redirect -> context.getString(R.string.catalogue_error_redirect)
        DownloadFailure.NotAWebPage -> context.getString(R.string.catalogue_error_html)
        is DownloadFailure.NotAFeed -> context.getString(
            R.string.catalogue_error_not_a_feed,
            failure.contentType ?: context.getString(R.string.catalogue_error_unknown_type),
        )
        DownloadFailure.Malformed -> context.getString(R.string.catalogue_error_malformed)
        is DownloadFailure.Http -> context.getString(R.string.catalogue_error_http, failure.status)
        DownloadFailure.NoHost -> context.getString(R.string.catalogue_error_no_host)
        DownloadFailure.TimedOut -> context.getString(R.string.catalogue_error_timed_out)
        DownloadFailure.Unreachable -> context.getString(R.string.catalogue_error_unreachable)
        DownloadFailure.Unknown -> context.getString(R.string.downloads_failure_unknown)
    }
}
