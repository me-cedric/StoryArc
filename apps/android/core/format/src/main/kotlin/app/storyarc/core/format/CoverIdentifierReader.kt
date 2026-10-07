package app.storyarc.core.format

import app.storyarc.core.model.CoverIdentifier
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat

/**
 * The identifier a publication carries, read on demand for the cover lookup.
 *
 * Task 6.1 of `cover-for-every-publication`. Read when the lookup rung asks, not at index
 * time: `Publication` has no identifier field, and adding one would need a migration of the
 * stored library for a value only a reader who turned the lookup on ever uses. iOS's
 * `CoverIdentifierReader` is its twin.
 */
object CoverIdentifierReader {

    private val isbnPrefix = Regex("^(urn:)?isbn:", RegexOption.IGNORE_CASE)

    /** An ISBN from an EPUB's package document, an ASIN or release group from audio tags. */
    suspend fun identifier(publication: Publication, source: RandomAccessSource): CoverIdentifier? =
        when (publication.format) {
            PublicationFormat.EPUB -> epubIsbn(source)
            PublicationFormat.M4B, PublicationFormat.MP3, PublicationFormat.FLAC,
            PublicationFormat.OGG, PublicationFormat.AUDIO_FOLDER ->
                AudioTagIdentifiers.identifier(source)
            else -> null
        }

    private suspend fun epubIsbn(source: RandomAccessSource): CoverIdentifier? =
        runCatching { EpubReader.open(source).metadata.identifiers }.getOrNull()
            ?.firstNotNullOfOrNull(::isbn)

    /** An ISBN as an OPF writes it: bare, hyphenated, or behind `urn:isbn:`. */
    internal fun isbn(text: String): CoverIdentifier? =
        CoverIdentifier.isbn(text.trim().replace(isbnPrefix, ""))
}
