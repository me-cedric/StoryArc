package app.storyarc.core.model

import java.util.Locale
import java.util.UUID

/**
 * An identifier a publication carries that some open catalogue can answer with a cover.
 *
 * Three cases, because three keyless providers exist and each answers one of them. A fourth
 * identifier with no provider behind it would be a value nothing can use, so this hierarchy
 * and the provider list are deliberately the same length.
 *
 * iOS's `CoverIdentifier` makes the same three cases in the same order.
 */
sealed class CoverIdentifier {
    /**
     * The identifier's own characters, which is the whole of what leaves the device.
     *
     * `cover-art` says a lookup "sends the identifier and nothing else: no library listing,
     * no reading history, no device identifier". This property is what a test asserts that
     * against, because the request is built from it and from nothing else.
     */
    abstract val value: String

    /** A book's ISBN, as an EPUB's OPF states it. Ten or thirteen digits, no hyphens. */
    data class Isbn(override val value: String) : CoverIdentifier()

    /** A MusicBrainz release-group id, which an audiobook ripped from CDs often carries. */
    data class MusicBrainzReleaseGroup(override val value: String) : CoverIdentifier()

    /** An Audible ASIN, which an Audible-sourced audiobook carries. */
    data class AudibleAsin(override val value: String) : CoverIdentifier()

    /**
     * The provider this identifier belongs to.
     *
     * A property rather than a lookup table: the pairing is one to one, and it is the whole
     * reason the identifier is modelled at all.
     */
    val provider: CoverLookupProvider
        get() = when (this) {
            is Isbn -> CoverLookupProvider.OPEN_LIBRARY
            is MusicBrainzReleaseGroup -> CoverLookupProvider.COVER_ART_ARCHIVE
            is AudibleAsin -> CoverLookupProvider.AUDNEXUS
        }

    companion object {
        /**
         * Reads an ISBN a file stated, or refuses it.
         *
         * Hyphens and spaces are how an OPF usually writes one, and they are not part of the
         * number. Everything else is refused here rather than at the provider: a malformed
         * identifier in a URL is a request that can only fail, and `cover-art` allows one
         * request per publication, so a wasted one is the only one that publication gets.
         */
        fun isbn(text: String): CoverIdentifier? {
            val digits = text.filterNot { it.isWhitespace() || it == '-' }.uppercase(Locale.ROOT)
            if (digits.length != 10 && digits.length != 13) return null
            if (!digits.dropLast(1).all { it.isDigit() }) return null
            val check = digits.last()
            if (!check.isDigit() && !(digits.length == 10 && check == 'X')) return null
            return Isbn(digits)
        }

        /** Reads a MusicBrainz release-group id, which is a UUID and nothing else. */
        fun musicBrainz(text: String): CoverIdentifier? {
            val trimmed = text.trim()
            val parsed = runCatching { UUID.fromString(trimmed) }.getOrNull() ?: return null
            return MusicBrainzReleaseGroup(parsed.toString())
        }

        /** Reads an Audible ASIN: ten characters, letters and digits, as Audible mints them. */
        fun asin(text: String): CoverIdentifier? {
            val trimmed = text.trim().uppercase(Locale.ROOT)
            if (trimmed.length != 10 || !trimmed.all { it.isLetterOrDigit() }) return null
            return AudibleAsin(trimmed)
        }
    }
}

/**
 * An open catalogue StoryArc may ask for a cover, once a reader turns the lookup on.
 *
 * All three need no API key and no owner account, which is what keeps this feature from
 * becoming a task for whoever runs the server. `design.md` records why Google Books is not
 * here: it needs a key the owner must create, and its terms put another brand on StoryArc's
 * publication page.
 */
enum class CoverLookupProvider {
    OPEN_LIBRARY,
    COVER_ART_ARCHIVE,
    AUDNEXUS,
    ;

    /**
     * The name the setting shows, so a reader reads who would be asked before they agree.
     *
     * Not localised: these are the catalogues' own names, and translating a proper noun
     * would stop a reader recognising the service they are being told about.
     */
    val displayName: String
        get() = when (this) {
            OPEN_LIBRARY -> "Open Library"
            COVER_ART_ARCHIVE -> "Cover Art Archive"
            AUDNEXUS -> "Audnexus"
        }

    /**
     * The host a request to this provider reaches.
     *
     * The other half of what the setting states: a reader reads the name and can see the
     * address it resolves to.
     */
    val host: String
        get() = when (this) {
            OPEN_LIBRARY -> "covers.openlibrary.org"
            COVER_ART_ARCHIVE -> "coverartarchive.org"
            AUDNEXUS -> "api.audnex.us"
        }

    /**
     * Whether the answer is the picture itself or a document that names where it is.
     *
     * Open Library and the Cover Art Archive answer with the image. Audnexus answers with a
     * book document whose `image` field holds the address. One property decides it, so the
     * client keeps one code path instead of three.
     */
    val answersWithImage: Boolean get() = this != AUDNEXUS
}

/** Where one identifier is asked about, and nowhere else. */
object CoverLookupRequest {
    /**
     * The single address this identifier is looked up at.
     *
     * `default=false` on Open Library matters. Without it the service answers a blank
     * placeholder with status 200, and the app would store a grey rectangle as the reader's
     * cover and never ask again.
     */
    fun url(identifier: CoverIdentifier): String = when (identifier) {
        is CoverIdentifier.Isbn ->
            "https://covers.openlibrary.org/b/isbn/${identifier.value}-L.jpg?default=false"
        is CoverIdentifier.MusicBrainzReleaseGroup ->
            "https://coverartarchive.org/release-group/${identifier.value}/front"
        is CoverIdentifier.AudibleAsin ->
            "https://api.audnex.us/books/${identifier.value}"
    }
}
