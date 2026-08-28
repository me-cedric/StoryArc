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
