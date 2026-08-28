package app.storyarc.core.kavita

import kotlinx.serialization.Serializable

/**
 * One of a Kavita server's libraries.
 *
 * `kavita-server` requires the app to "mirror Kavita's own structure -- libraries, series,
 * volumes, and chapters -- rather than flattening it". A reader who arranged their server
 * into Comics and Books arranged it for a reason.
 */
@Serializable
data class KavitaLibraryFolder(val id: Int, val name: String)

/** A series, as the library list shows it. */
@Serializable
data class KavitaSeries(
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
    val title: String? = null,
    val pages: Int = 0,
    val pagesRead: Int = 0,
) {
    /**
     * What to call it in a list.
     *
     * The title when the server has one, the number when it does not. Kavita leaves the
     * title empty for a plain numbered issue, and "3" beats an empty row.
     */
    val displayName: String get() = title?.takeIf { it.isNotEmpty() } ?: number

    val isFinished: Boolean get() = pages > 0 && pagesRead >= pages
}

/** A volume, which is a named group of chapters. */
@Serializable
data class KavitaVolume(
    val id: Int,
    val number: Int = 0,
    val name: String? = null,
    val chapters: List<KavitaChapter> = emptyList(),
) {
    /**
     * Whether this is Kavita's holder for chapters that belong to no volume.
     *
     * Kavita models loose chapters as a volume numbered zero. `kavita-server` requires the
     * detail screen to list "volumes and loose chapters in Kavita's own order, clearly
     * distinguishing the two" -- without the distinction, every series with loose chapters
     * shows a phantom "Volume 0".
     */
    val isLooseChapters: Boolean get() = number == 0
}

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
    val ageRating: Int = 0,
    val releaseYear: Int = 0,
    val publicationStatus: Int = 0,
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
