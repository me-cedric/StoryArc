package app.storyarc.feature.reader

/**
 * Where a chapter starts inside this publication: `ComicInfo`'s bookmarks. Android has
 * no PDF outline (ADR-0012), unlike iOS's `ReaderModel.chapterStartIndices`.
 */
internal fun ReaderViewModel.chapterStartIndices(): List<Int> = archive?.chapterStartIndices.orEmpty()

/**
 * Where this publication's chapters start, and what to call each one.
 *
 * `page-browser-carousel`: the carousel and the slider's ticks both read this. Android
 * reads no PDF outline (ADR-0012), so a comic archive is the only source.
 */
internal fun ReaderViewModel.chapterMarkers(): List<ChapterMarker> =
    ChapterBrowser.markers(
        comicStarts = archive?.chapterStartIndices.orEmpty(),
        titles = archive?.chapterTitles.orEmpty(),
    )
