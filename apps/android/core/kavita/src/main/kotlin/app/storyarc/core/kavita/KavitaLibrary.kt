package app.storyarc.core.kavita

import kotlinx.serialization.ExperimentalSerializationApi
import app.storyarc.core.model.SENTINEL_NAMES
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNames

/**
 * One of a Kavita server's libraries.
 *
 * `kavita-server` requires the app to "mirror Kavita's own structure -- libraries, series,
 * volumes, and chapters -- rather than flattening it". A reader who arranged their server
 * into Comics and Books arranged it for a reason.
 */
@Serializable
data class KavitaLibraryFolder(val id: Int, val name: String)

/**
 * One clause of Kavita's series filter.
 *
 * `field` 19 is `Libraries` in `SeriesFilterField.cs`, line 29. `comparison` 0 narrowed a
 * live server on 2026-09-06, so it is the value this app sends. `value` is a string on the
 * wire even when it names a number, which is how Kavita's own client sends it.
 */
@Serializable
internal data class KavitaFilterStatement(
    val comparison: Int,
    val field: Int,
    val value: String,
)

/**
 * Kavita's `SeriesFilterV2Dto`, of the parts this app sends.
 *
 * The DTO also carries `id`, `name` and `sortOptions`. This app sends the two fields it has
 * a use for, because a field nobody measured is a field this client cannot claim a meaning
 * for. `combination` 0 is `FilterCombination.And`.
 */
@Serializable
internal data class KavitaFilter(
    val statements: List<KavitaFilterStatement>,
    // No default. `kotlinx.serialization` leaves a field holding its default out of the
    // encoded body, and the body measured against a live server on 2026-09-06 carried
    // `"combination":0`. A filter that quietly dropped it would be a shape nobody measured.
    val combination: Int,
) {
    companion object {
        private const val LIBRARY_FIELD = 19
        private const val MEASURED_COMPARISON = 0

        /** `FilterCombination.And`, which is what one statement needs and more would want. */
        private const val AND = 0

        fun ofLibrary(id: Int) = KavitaFilter(
            listOf(KavitaFilterStatement(MEASURED_COMPARISON, LIBRARY_FIELD, id.toString())),
            AND,
        )
    }
}

/** A series, as the library list shows it. */
@Serializable
data class KavitaSeries(
    /**
     * A search result spells this `seriesId` where a library listing spells it `id`. Both
     * are read: decoded through only one of them, a found series comes back as series zero
     * and opens nothing.
     */
    @OptIn(ExperimentalSerializationApi::class)
    @JsonNames("seriesId")
    val id: Int,
    val name: String,
    val libraryId: Int = 0,
    /**
     * Pages in the whole series, and how many the server says are read. Defaulted rather
     * than required: Kavita's search results carry a series' identity and not its progress,
     * and a decoder that insisted would turn every search into "unexpected response".
     */
    val pages: Int = 0,
    val pagesRead: Int = 0,
    /**
     * Kavita's `MangaFormat`: 0 image, 1 archive, 2 unknown, 3 epub, 4 pdf.
     *
     * Defaulted, because a search result does not carry it. Read by the library, which has
     * to file a server's publication under a format before anything is downloaded --
     * `KavitaContributor.format` is where the mapping and its one guess live.
     */
    val format: Int = 0,
) {
    /**
     * How far through, for the progress a series row shows.
     *
     * Null for a series with no pages rather than zero: a server still scanning reports
     * nothing, and a bar at zero would say "unread" about something it does not yet know.
     */
    val fraction: Double?
        get() = if (pages <= 0) null else minOf(1.0, pagesRead.toDouble() / pages.toDouble())
}

/** A chapter -- the thing a reader actually opens. */
@Serializable
data class KavitaChapter(
    val id: Int,
    /** Kavita's own chapter number, as a string because it can be `1`, `1.5` or `Special`. */
    val number: String = "",
    /**
     * A search result spells this `titleName` where a volume spells it `title`. Kavita's two
     * DTOs differ, and a chapter found by name would otherwise be listed as a bare number.
     */
    @OptIn(ExperimentalSerializationApi::class)
    @JsonNames("titleName")
    val title: String? = null,
    val pages: Int = 0,
    val pagesRead: Int = 0,
    /**
     * Which series it belongs to, when the answer said.
     *
     * Zero inside a volume, where the series is the screen the reader is already on. A search
     * result is the case that needs it: a chapter found by name is the only kind of row that
     * arrives with no series around it, and without this it could be listed and not opened.
     */
    val seriesId: Int = 0,
) {
    /**
     * The chapter's issue number, or null where Kavita is saying it has none.
     *
     * **`-100000` is a sentinel, not a number.** Kavita writes it for a chapter with no
     * number at all -- a collected edition, a volume with one part -- and any negative is
     * treated the same way, because none of them is an issue number. One place, here,
     * because every screen that draws a chapter needs the same answer and the ones that
     * asked separately disagreed: a reader met "-100000" as a row in a chapter list, as
     * "Continue -100000", and as the name of a downloaded file.
     */
    val issueNumber: String? get() = number.takeIf { it.isNotBlank() && !it.startsWith("-") }

    /**
     * What to call it in a list, or empty when the server gave nothing to call it.
     *
     * The title when the server has one, the number when it does not, and *nothing* when
     * the number is the sentinel -- an empty string rather than a made-up label, because
     * what to say instead is the screen's decision and a screen has its own words for it.
     * Kavita leaves the title empty for a plain numbered issue, and "3" beats an empty row.
     */
    val displayName: String get() = properTitle ?: issueNumber.orEmpty()

    /**
     * The chapter's own title, or null where the server sent a number wearing one.
     *
     * Kavita fills a chapter's title from its own range when nothing else named it, so the
     * sentinel arrives in the title as readily as in the number. [issueNumber] was guarded
     * and this was not, which left the guard reachable around: a title of "-100000" wins
     * before `issueNumber` is ever read, and every screen draws the title first.
     *
     * A trust boundary, so it is checked rather than assumed. No book is called "-100000".
     */
    val properTitle: String? get() = title?.takeIf { it.isNotBlank() && it !in SENTINEL_NAMES }

    val isFinished: Boolean get() = pages > 0 && pagesRead >= pages
}

/** A volume, which is a named group of chapters. */
@Serializable
data class KavitaVolume(
    val id: Int,
    val number: Int = 0,
    /**
     * What Kavita's own code asks when it wants to know what a volume is.
     *
     * `VolumeExtensions.IsLooseLeaf()` reads `MinNumber`, not `Number`; the integer
     * `number` is the older field beside it. A server that sends only the newer one would
     * leave `number` at its default and a specials volume would be headed "Chapters",
     * which is the wrong one of the two right answers. So this is read first where it came.
     */
    val minNumber: Double? = null,
    val name: String? = null,
    val chapters: List<KavitaChapter> = emptyList(),
) {
    /**
     * The number to judge this volume by: Kavita's own field, then the older one.
     *
     * `minNumber` is a float on the wire because a volume can be `1.5`. A sentinel is a
     * whole number, so comparing the rounded value loses nothing that matters here.
     */
    private val kind: Int get() = minNumber?.toInt() ?: number

    /**
     * Whether this is Kavita's holder for chapters that belong to no volume.
     *
     * `kavita-server` requires the detail screen to list "volumes and loose chapters in
     * Kavita's own order, clearly distinguishing the two" -- without the distinction, every
     * series with loose chapters shows a heading the server never meant as one.
     *
     * **Two numbers, because Kavita changed its mind.** Older servers held loose chapters in
     * a volume numbered zero; current ones use [LOOSE_LEAF_VOLUME]. Both are accepted, so a
     * reader on either server sees the same screen.
     */
    val isLooseChapters: Boolean get() = kind == LOOSE_LEAF_VOLUME || kind == 0

    /**
     * Whether this is Kavita's holder for specials -- annuals, one-shots, anything filed
     * outside the run.
     *
     * A third kind, and the reason the heading needs three cases rather than two: this
     * volume has no case of its own, so a reader met "100000" as a heading.
     */
    val isSpecials: Boolean get() = kind == SPECIAL_VOLUME

    /**
     * The volume's own name, or null where the server sent its number wearing one.
     *
     * Kavita derives a volume's name from its number, so the name of a sentinel-numbered
     * volume is the sentinel as a string. The heading falls back to the number for a real
     * volume, and a real volume's number is not a sentinel, so nothing can reach a reader.
     */
    val properName: String? get() = name?.takeIf { it.isNotBlank() && it !in SENTINEL_NAMES }
}

/**
 * Kavita's holder for chapters that belong to no volume.
 *
 * Quoted from `Kavita.Models/Constants/ParserConstants.cs`:
 * `public const int LooseLeafVolumeNumber = -100_000;`
 */
const val LOOSE_LEAF_VOLUME: Int = -100_000

/**
 * Kavita's holder for specials.
 *
 * Quoted from the same file: `public const int SpecialVolumeNumber = 100_000;`. **It is
 * positive**, so a guard written against negative sentinels does not catch it. That is how
 * this one was missed while the chapter sentinel beside it was already guarded.
 */
const val SPECIAL_VOLUME: Int = 100_000


/** A name the server holds for a genre, a tag, a person or a publisher. */
@Serializable
data class KavitaNamed(
    val id: Int = 0,
    val title: String? = null,
    val name: String? = null,
) {
    /** Kavita calls a genre's name `title` and a person's name `name`. Either will do. */
    val label: String get() = title?.takeIf { it.isNotEmpty() } ?: name.orEmpty()
}

/**
 * What the server holds about a series.
 *
 * `kavita-server` requires this to be preferred over metadata embedded in the file, because
 * the server is the curated source. Cached with the download so it survives the server
 * being unreachable.
 */
@Serializable
data class KavitaMetadata(
    val seriesId: Int = 0,
    val summary: String? = null,
    val genres: List<KavitaNamed> = emptyList(),
    val tags: List<KavitaNamed> = emptyList(),
    val writers: List<KavitaNamed> = emptyList(),
    val publishers: List<KavitaNamed> = emptyList(),
    /**
     * A position in Kavita's own `AgeRating` enum. Zero is Kavita's own `Unknown`, which is
     * what a series nobody rated carries -- so the absence needs no shape of its own here.
     */
    val ageRating: Int = 0,
    val releaseYear: Int = 0,
    /**
     * A position in Kavita's own `PublicationStatus` enum, or `null` when the answer stated
     * none.
     *
     * **Nullable rather than a number with a default, because Kavita's range starts at a
     * state.** Zero is `OnGoing` -- a state a curator chose -- so a field defaulted to zero
     * makes an answer that omits `publicationStatus` indistinguishable from an answer that
     * says the series is running, and the app would say it is running on the server's behalf.
     */
    val publicationStatus: Int? = null,
) {
    /** The people worth naming on a detail screen, in the order a reader looks for them. */
    val people: List<String> get() = (writers + publishers).map { it.label }.filter { it.isNotEmpty() }

    /** Genres and tags read as one list; the distinction is Kavita's, not the reader's. */
    val subjects: List<String> get() = (genres + tags).map { it.label }.filter { it.isNotEmpty() }
}

/**
 * Where a reader got to in one chapter, in the shape Kavita's own progress endpoint wants.
 *
 * The whole chain, not the chapter alone: Kavita keys its progress rows by library, series,
 * volume and chapter together, and a post missing one of them is refused.
 */
@Serializable
data class KavitaPosition(
    val libraryId: Int,
    val seriesId: Int,
    val volumeId: Int,
    val chapterId: Int,
    val pageNum: Int,
)

/** Which chapter to mark, in the shape Kavita's mark endpoints want. */
@Serializable
data class KavitaMark(val seriesId: Int, val chapterId: Int)

/**
 * A file the server sent, with the type it declared.
 *
 * The type is not decoration: a Kavita library holds comics and books alike, and the reader
 * the app opens is chosen by what the file is.
 */
data class KavitaFile(val bytes: ByteArray, val mediaType: String?) {
    override fun equals(other: Any?): Boolean =
        other is KavitaFile && mediaType == other.mediaType && bytes.contentEquals(other.bytes)

    override fun hashCode(): Int = 31 * bytes.contentHashCode() + mediaType.hashCode()
}
