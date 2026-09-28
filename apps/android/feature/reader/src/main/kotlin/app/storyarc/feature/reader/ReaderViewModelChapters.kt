package app.storyarc.feature.reader

/**
 * Where a chapter starts inside this publication: `ComicInfo`'s bookmarks. Android has
 * no PDF outline (ADR-0012), unlike iOS's `ReaderModel.chapterStartIndices`.
 */
internal fun ReaderViewModel.chapterStartIndices(): List<Int> = archive?.chapterStartIndices.orEmpty()
