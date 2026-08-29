package app.storyarc.core.model

import java.util.UUID

/**
 * Whether a publication can be read without transferring all of it.
 *
 * Three states, not two. `publication-formats` needs to distinguish a format that
 * streams from one that must be downloaded first *and* from one that cannot be
 * read at all — collapsing the last two would either promise a download that
 * changes nothing, or refuse a book that would open fine once local.
 */
enum class StreamingCapability {
    /** Pages can be fetched individually from a remote source. */
    STREAMS,

    /**
     * Readable, but only once the whole file is local. A solid RAR5, say: every
     * entry before the target has to be decompressed.
     */
    DOWNLOAD_ONLY,

    /**
     * Cannot be read at all, local or remote. A solid RAR4: no decoder with an
     * OSI-approved licence implements one, so downloading changes nothing.
     */
    REFUSED,
}

/**
 * Where a value came from, which decides whether it may be silently replaced.
 *
 * `publication-formats` requires values parsed from a filename to be marked
 * inferred, so a later authoritative source can overwrite them without asking the
 * user to resolve a conflict the app invented. The distinction only matters at the
 * moment of replacement, which is exactly when it is too late to reconstruct.
 */
enum class MetadataOrigin {
    /** Read from the publication: `ComicInfo.xml`, an EPUB package document. */
    EMBEDDED,

    /** Guessed from the filename. */
    INFERRED,

    /** Supplied by a server or catalogue that owns the answer. */
    AUTHORITATIVE,

    ;

    /**
     * Whether a value from [other] may replace one from this without asking.
     *
     * Ordered by how much the source knows: an inferred value yields to anything,
     * embedded metadata yields only to an authoritative source, and an
     * authoritative value is never silently overwritten.
     */
    fun yieldsTo(other: MetadataOrigin): Boolean = rank < other.rank

    private val rank: Int
        get() = when (this) {
            INFERRED -> 0
            EMBEDDED -> 1
            AUTHORITATIVE -> 2
        }
}

/**
 * The container formats a publication can arrive in.
 *
 * Lives in the domain rather than the format layer because the library sorts,
 * filters and explains by format, and none of that should require the parser.
 */
enum class PublicationFormat {
    CBZ, CBR, CB7, CBT, EPUB, PDF, IMAGE_FOLDER,
    ;

    /**
     * Whether pages are images rather than reflowable text. Drives which reader
     * opens the publication, and whether a page curl needs a raster.
     */
    val isPagedImages: Boolean
        get() = when (this) {
            CBZ, CBR, CB7, CBT, IMAGE_FOLDER -> true
            EPUB, PDF -> false
        }

    /**
     * The media type that names this format, for a record that has to be read back.
     *
     * The inverse of [ofMediaType], and it has to stay the inverse: a download record keeps
     * a media type and the store names the file on disk from it, so a type that did not
     * round-trip would write `x.cbz` and later go looking for `x.bin`.
     */
    val mediaType: String
        get() = when (this) {
            CBZ -> "application/vnd.comicbook+zip"
            CBR -> "application/vnd.comicbook-rar"
            CB7 -> "application/vnd.comicbook+7z"
            CBT -> "application/vnd.comicbook+tar"
            EPUB -> "application/epub+zip"
            PDF -> "application/pdf"
            // A folder of images is not a type anybody publishes, and it round-trips
            // through nothing. Named rather than defaulted so the `when` stays exhaustive,
            // and answered honestly so a caller that needs one file can see there is none.
            IMAGE_FOLDER -> "inode/directory"
        }

    /**
     * Whether StoryArc can open a publication in this format today.
     *
     * CB7 is the one that parses as a format and does not open: `publication-formats`
     * records 7-Zip as an open question, and the app names the refusal rather than
     * pretending the file is not there.
     */
    val isOpenable: Boolean get() = this != CB7

    /**
     * How the format is named to a person — in a refusal, a filter, a detail row.
     *
     * `publication-formats` forbids a generic failure, and a name is what makes the
     * difference between "7-Zip is not supported" and "could not open file".
     */
    val displayName: String
        get() = when (this) {
            CBZ -> "CBZ"
            CBR -> "CBR"
            CB7 -> "CB7"
            CBT -> "CBT"
            EPUB -> "EPUB"
            PDF -> "PDF"
            IMAGE_FOLDER -> "Folder"
        }

    companion object {
        /**
         * The format a media type names, when it names one this app can read.
         *
         * For a catalogue, where the file has not been fetched and its type is all there
         * is. `opds-catalog` needs this twice: to pick the best acquisition when several
         * are offered, and to mark an entry unreadable when none of them map.
         *
         * Parameters after a semicolon are ignored — several servers append
         * `;charset=utf-8` to `application/epub+zip`, and an exact-match table would call
         * that unreadable.
         */
        fun ofMediaType(mediaType: String): PublicationFormat? =
            when (mediaType.substringBefore(';').trim().lowercase()) {
                "application/epub+zip" -> EPUB
                "application/pdf" -> PDF
                "application/vnd.comicbook+zip", "application/x-cbz" -> CBZ
                "application/vnd.comicbook-rar", "application/x-cbr" -> CBR
                "application/vnd.comicbook+tar", "application/x-cbt" -> CBT
                // Listed so a catalogue entry can be *named* as unreadable rather than
                // dropped. `publication-formats` leaves CB7 undecoded, and the refusal has
                // to say which format it refused.
                "application/vnd.comicbook+7z", "application/x-cb7" -> CB7
                else -> null
            }
    }
}

/**
 * One thing a person can read.
 *
 * The library's unit. Assembled by indexing a file — the format layer reads the
 * container and its metadata, and this is what comes out the other side, with no
 * reference to how it was obtained.
 */
data class Publication(
    /**
     * Stable across sources, so the same book from a folder and from a server is
     * one book with one reading position (ADR-0006).
     */
    val identity: PublicationIdentity,
    val format: PublicationFormat,
    /**
     * How the publication is presented: the title if it has one, else the series
     * and number, else the filename.
     */
    val displayTitle: String,
    val series: String? = null,
    /** Issue or chapter. A string: "3.5" and "Annual 1" are both real. */
    val number: String? = null,
    val volume: Int? = null,
    val authors: List<String> = emptyList(),
    val publisher: String? = null,
    val year: Int? = null,
    val language: String? = null,
    val summary: String? = null,
    /** Where the metadata above came from, and therefore what may replace it. */
    val origin: MetadataOrigin,
    /**
     * Pages for a comic, spine items for an EPUB. `null` when the publication
     * could not be indexed deeply enough to know.
     */
    val pageCount: Int? = null,
    /** Entries that looked like pages and could not be read. */
    val skippedPageCount: Int = 0,
    /** The path of the cover *inside* the publication, when it has one. */
    val coverPath: String? = null,
    val readingDirection: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT,
    val isFixedLayout: Boolean = false,
    val streaming: StreamingCapability = StreamingCapability.STREAMS,
    /**
     * Which source this came from, when the app knows.
     *
     * `library-browsing` asks the library to combine sources and to list "titles from
     * higher sources first when two sources hold the same publication", and `sources` asks
     * a source's detail screen for its item count. Neither is answerable without this,
     * which is why a flat list of files was as far as the library could go.
     *
     * Nullable, because a publication can arrive without one: a file the system hands over
     * belongs to no source the reader configured. Null means unattributed rather than
     * unknown-and-probably-local.
     *
     * Assigned by the library rather than by the indexer: indexing decides what a
     * publication *is*, and the indexer reads bytes and has no idea a registry exists.
     */
    val sourceId: UUID? = null,
) {
    /** A stable key for lists and diffing. See [PublicationIdentity.stableId]. */
    val id: String get() = identity.stableId

    /**
     * Whether the reader can open this at all.
     *
     * False only for [StreamingCapability.REFUSED]. A download-only publication is
     * openable — it just has to arrive first, which is the library's problem and
     * not the reader's.
     */
    val isOpenable: Boolean get() = streaming != StreamingCapability.REFUSED

    /** Whether some pages are missing from what the reader will show. */
    val isPartial: Boolean get() = skippedPageCount > 0
}
