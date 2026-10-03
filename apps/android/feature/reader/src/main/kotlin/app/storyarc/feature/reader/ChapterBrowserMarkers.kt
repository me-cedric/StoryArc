package app.storyarc.feature.reader

/**
 * A chapter's start, for the page browser carousel and the page slider's ticks.
 *
 * `page-browser-carousel`: the carousel names "the centred page's chapter" and marks
 * "the first page of each chapter" with a badge; the slider marks "a tick at the start
 * of each chapter". One marker answers both: where the chapter starts, and what to
 * call it. iOS's `ChapterMarker` is the same pair.
 */
internal data class ChapterMarker(val index: Int, val title: String?)

/**
 * What the carousel says above itself, free of the localized string it becomes.
 *
 * A marker's title names the chapter; without one, the name is the chapter's position
 * among the chapters. Carrying only the position (not the finished "Chapter %d") is
 * what lets a test check the number without building a `Text`.
 */
internal sealed class ChapterLabel {
    data class Named(val title: String) : ChapterLabel()
    data class Position(val position: Int) : ChapterLabel()
}

/**
 * The rules the carousel and the slider share, free of any view so a test can reach
 * them without composing one. iOS's `ChapterBrowser` is the same table.
 */
internal object ChapterBrowser {
    /**
     * Markers built from a comic archive's declared chapter starts and their titles.
     *
     * `ComicArchiveReading.chapterStartIndices` is already filtered to pages the
     * archive actually has (`PageDeclarations.chapterStarts`); a title missing from
     * `titles` is a start with a blank or absent `Bookmark` text. Android reads no PDF
     * outline (ADR-0012), so this is the only source of markers here.
     */
    fun markers(comicStarts: List<Int>, titles: Map<Int, String>): List<ChapterMarker> =
        comicStarts.sorted().map { ChapterMarker(it, titles[it]) }

    /**
     * The marker in force at `index`: the last one whose start is at or before it.
     *
     * `null` before the first chapter starts — a publication need not open on one.
     */
    fun activeMarker(index: Int, markers: List<ChapterMarker>): ChapterMarker? =
        markers.filter { it.index <= index }.maxByOrNull { it.index }

    /**
     * What the carousel names above itself for the page at `index`.
     *
     * `null` with no markers at all — the "No chapter markers" scenario draws nothing —
     * and before the first chapter starts, which a publication need not open on.
     */
    fun chapterLabel(index: Int, markers: List<ChapterMarker>): ChapterLabel? {
        if (markers.isEmpty()) return null
        val marker = activeMarker(index, markers) ?: return null
        if (!marker.title.isNullOrEmpty()) return ChapterLabel.Named(marker.title)
        val sorted = markers.sortedBy { it.index }
        val position = sorted.indexOfFirst { it.index == marker.index } + 1
        return ChapterLabel.Position(position)
    }

    /**
     * The badge text for a chapter's first page, or `null` when `index` does not start
     * one.
     *
     * design.md §5: "the issue number the marker gives … without a number, the
     * chapter's position." A marker's title is read as a number when it is nothing but
     * digits — the one shape a free-text `Bookmark` can give unambiguously.
     */
    fun badgeText(index: Int, markers: List<ChapterMarker>): String? {
        val sorted = markers.sortedBy { it.index }
        val position = sorted.indexOfFirst { it.index == index }
        if (position < 0) return null
        issueNumber(sorted[position].title)?.let { return "#$it" }
        return "#${position + 1}"
    }

    private val trailingIssue = Regex("#\\s*(\\d+)\\s*$")

    /**
     * The issue number a marker's title gives: the whole title when it is only digits, or a
     * trailing "#4", as in "Green Lantern (2005) #4".
     */
    fun issueNumber(title: String?): String? = when {
        title.isNullOrEmpty() -> null
        title.all { it.isDigit() } -> title
        else -> trailingIssue.find(title)?.groupValues?.get(1)
    }

    /**
     * Where each chapter start falls along the slider, as a fraction of its track.
     *
     * Empty with one page or none: there is no track to place a fraction on.
     */
    fun tickFractions(markers: List<ChapterMarker>, pageCount: Int): List<Float> {
        if (pageCount <= 1) return emptyList()
        return markers.map { it.index.toFloat() / (pageCount - 1).toFloat() }
    }

    /**
     * The carousel's own visual position for a publication index, under a reading
     * direction.
     *
     * `page-browser-carousel` §1: "Keep the Ltr { } pin and the reversed order for
     * right-to-left" — [Ltr] pins the ambient layout, so this is the data-level mirror
     * that puts page one at the carousel's right end instead. [Paging.readingOrderStep]
     * is the same mirror for the pager.
     */
    fun displayIndex(index: Int, pageCount: Int, isRightToLeft: Boolean): Int =
        if (isRightToLeft) pageCount - 1 - index else index
}
