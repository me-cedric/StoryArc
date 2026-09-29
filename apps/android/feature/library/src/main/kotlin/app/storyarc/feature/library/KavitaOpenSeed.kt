package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaExchange
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore

/**
 * Writes down what the server already reports, for a chapter this device has never opened.
 *
 * The rule is [KavitaExchange.openSeed], outside the composables, so a test can call it
 * without a screen. The record is stamped as synchronised: the position came from the
 * server, so the server already holds it, and the next pull must not read it as a change
 * made on this device.
 */
internal suspend fun seedKavitaOpen(
    publication: Publication,
    pagesRead: Int,
    pages: Int,
    progress: ProgressStore?,
) {
    if (progress == null) return
    val position = KavitaExchange.openSeed(
        pagesRead = pagesRead,
        pages = pages,
        existing = progress.progress(publication.identity),
        // The EPUB reader opens only a reflowable position; `AppShell` routes the rest.
        reflowable = publication.format == PublicationFormat.EPUB && !publication.isFixedLayout,
    ) ?: return
    val seeded = ReadingProgress(
        identity = publication.identity,
        position = position,
        updatedAtEpochMillis = System.currentTimeMillis(),
    )
    progress.save(KavitaExchange.settled(seeded))
}
