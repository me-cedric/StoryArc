package app.storyarc.feature.epubreader

import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.TotalProgression
import app.storyarc.core.model.isScroll

/**
 * Whether the page on screen is the last page of the book.
 *
 * Readium's locator names where the visible page starts. A short last page starts well
 * before 99.9 %, so the locator alone never says "finished". The paginated web view reports
 * which page of its resource is on screen: the last page of the last resource in the
 * reading order is the end of the book. Scroll mode reports each resource as one page, so
 * there this is always false and the locator's total is the only rule. iOS reads the same
 * fact from the navigator's viewport, in `EpubReaderModel.isAtEnd`.
 */
internal fun isLastPage(
    pageIndex: Int,
    totalPages: Int,
    href: String,
    readingOrder: List<String>,
    transition: PageTransition,
): Boolean =
    !transition.isScroll && readingOrder.isNotEmpty() && totalPages > 0 &&
        pageIndex >= totalPages - 1 &&
        TotalProgression.indexOf(href, readingOrder) == readingOrder.lastIndex
