package app.storyarc.core.model

/**
 * Why a download stopped, as a code and its arguments rather than as a sentence.
 *
 * **A stored sentence keeps the language it was written in.** `localization` 15.9: the queue
 * wrote `offline-downloads`' "plain-language reason" into the record at the moment of failure,
 * and that record outlives the moment. A reader who then switched the app to French kept
 * reading an English refusal on every failed row, for ever -- the row is drawn from the store,
 * and the store held a finished sentence nothing could translate.
 *
 * So the record holds what happened and the screen says it. `DownloadFailureWords` is the
 * saying, in `feature:library`, where the strings are.
 *
 * **A closed set, never free text.** The same rule `IndexException` follows: a case the
 * compiler checks cannot have a sentence written into it by accident, and every case here has
 * to have a word in four languages before it can be drawn at all.
 *
 * iOS's `DownloadFailure` carries the same cases under the same names, with one difference
 * either way: it has no [ContentProtected], because its queue does not yet word a locked file
 * in its own sentence, and it has an `offline` that this one does not, because `URLError`
 * tells iOS that the device has no connection at all and `IOException` does not say so here. A
 * case a platform can never store is left out rather than given a word that is not true of it.
 */
sealed interface DownloadFailure {
    /**
     * A container StoryArc recognises and does not read, carrying the name so the sentence can
     * say "7-Zip" rather than "could not open file".
     */
    data class UnsupportedFormat(val format: String) : DownloadFailure

    /** The bytes arrived and were not a publication this app can open. */
    data object Unreadable : DownloadFailure

    /** The bytes are behind a store's content protection, which is not the same refusal. */
    data object ContentProtected : DownloadFailure

    /** The catalogue refused the sign-in it was given. */
    data object Unauthorized : DownloadFailure

    /** The server answered with nothing at all. */
    data object Empty : DownloadFailure

    /** An address this app will not follow -- not a web address, or a step down to cleartext. */
    data object RefusedAddress : DownloadFailure

    /** A redirect loop, or a redirect with no address to follow. */
    data object Redirect : DownloadFailure

    /** A web page where a catalogue was expected, which is usually a sign-in page. */
    data object NotAWebPage : DownloadFailure

    /** Something that is not a catalogue, carrying the content type when the server named one. */
    data class NotAFeed(val contentType: String?) : DownloadFailure

    /** A catalogue whose own bytes could not be parsed. */
    data object Malformed : DownloadFailure

    /** The server refused, carrying the status it refused with. */
    data class Http(val status: Int) : DownloadFailure

    /** The host could not be found. */
    data object NoHost : DownloadFailure

    /** The server did not answer in time. */
    data object TimedOut : DownloadFailure

    /** The server could not be reached, for a reason none of the above names. */
    data object Unreachable : DownloadFailure

    /**
     * What an older build's stored sentence becomes when the record is read.
     *
     * `localization` 15.9 asks for exactly this: an existing install must not show an empty
     * reason where it used to show an English one. The sentence itself is dropped rather than
     * kept -- it is in whichever language the app spoke when it was written, which is the
     * defect -- so the honest replacement is a reason that says only that the download failed.
     */
    data object Unknown : DownloadFailure

    /**
     * The record's own spelling: the code, and its argument after a newline when it has one.
     *
     * Newline-separated and code-first, the convention `OpdsCredential.stored` already uses in
     * this repository. A colon would be ambiguous -- a content type contains one.
     */
    val stored: String
        get() = when (this) {
            is UnsupportedFormat -> "unsupportedFormat\n$format"
            Unreadable -> "unreadable"
            ContentProtected -> "contentProtected"
            Unauthorized -> "unauthorized"
            Empty -> "empty"
            RefusedAddress -> "refusedAddress"
            Redirect -> "redirect"
            NotAWebPage -> "notAWebPage"
            is NotAFeed -> contentType?.let { "notAFeed\n$it" } ?: "notAFeed"
            Malformed -> "malformed"
            is Http -> "http\n$status"
            NoHost -> "noHost"
            TimedOut -> "timedOut"
            Unreachable -> "unreachable"
            Unknown -> "unknown"
        }

    companion object {
        /**
         * Reads back what [stored] wrote, and reads anything else as [Unknown].
         *
         * Anything else is a sentence an older build wrote, or a code a newer build knows and
         * this one does not. Both are reasons this build cannot say, and neither is a reason to
         * lose the download.
         */
        fun of(stored: String): DownloadFailure {
            val parts = stored.split("\n", limit = 2)
            val argument = parts.getOrNull(1)
            return when (parts[0]) {
                "unsupportedFormat" -> argument?.let { UnsupportedFormat(it) } ?: Unknown
                "unreadable" -> Unreadable
                "contentProtected" -> ContentProtected
                "unauthorized" -> Unauthorized
                "empty" -> Empty
                "refusedAddress" -> RefusedAddress
                "redirect" -> Redirect
                "notAWebPage" -> NotAWebPage
                "notAFeed" -> NotAFeed(argument)
                "malformed" -> Malformed
                "http" -> argument?.toIntOrNull()?.let { Http(it) } ?: Unknown
                "noHost" -> NoHost
                "timedOut" -> TimedOut
                "unreachable" -> Unreachable
                else -> Unknown
            }
        }
    }
}
