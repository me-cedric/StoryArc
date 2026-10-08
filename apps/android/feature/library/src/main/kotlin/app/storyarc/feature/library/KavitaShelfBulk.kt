package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaReadingListItem
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.kavita.KavitaVolume
import app.storyarc.core.persistence.KavitaOrigin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

/**
 * One chapter a server shelf holds, with everything a keep or a mark needs to name it.
 *
 * A collection holds series and a reading list holds chapters, so the two are brought to one
 * shape here and the actions below ask about chapters only. iOS's `KavitaShelfChapter` is its
 * twin.
 */
internal data class KavitaShelfChapter(
    val chapter: KavitaChapter,
    val series: KavitaSeries,
    val volumeId: Int,
    /** The file's size in bytes, or zero where the server stated none. */
    val bytes: Long,
) {
    val isFinished: Boolean get() = chapter.isFinished

    /** Where the chapter sits on the server, which a mark and a kept copy both have to name. */
    fun origin(sourceId: String) = KavitaOrigin(
        sourceId = sourceId,
        libraryId = series.libraryId,
        seriesId = series.id,
        volumeId = volumeId,
        chapterId = chapter.id,
        pages = chapter.pages,
    )
}

/** How large a whole-shelf download will be, in the three ways a server can leave it. */
internal sealed interface KavitaBulkSize {
    /** Every chapter stated its size, so this is the total. */
    data class Known(val bytes: Long) : KavitaBulkSize

    /** Some did not, so this is a floor and the sentence says so. */
    data class AtLeast(val bytes: Long) : KavitaBulkSize

    /** None did, so there is no number to give. */
    data object Unstated : KavitaBulkSize
}

/** What a whole-shelf download will copy: stated to the reader before anything starts. */
internal data class KavitaBulkDownloadAsk(
    val chapters: List<KavitaShelfChapter>,
    val size: KavitaBulkSize,
) {
    val count: Int get() = chapters.size
}

/** What a whole-shelf mark changed, so ten seconds later one tap can put it back. */
internal data class KavitaMarkUndo(val chapters: List<KavitaShelfChapter>, val read: Boolean)

/**
 * Acting on everything a server's collection or reading list holds.
 *
 * `collections-and-reading-lists`: a reader downloads "an entire collection or reading list"
 * and is told "the item count and total size before starting", or marks one read, "and the
 * action is undoable for 10 seconds". Every rule is here and free of the screen, so a test
 * states it without a composition. The screen asks these functions and draws their answers.
 */
internal object KavitaShelfBulk {

    /**
     * The process's own scope for what must outlive the screen that started it.
     *
     * On the main dispatcher, as the queue's own scope is: [DownloadQueue] keeps its waiting
     * callers and its records in plain maps and writes its library as read-then-set, so two
     * keeps started from two threads can lose a record. On one thread the keeps interleave
     * where they suspend and cannot overwrite one another.
     */
    val jobs = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * What the screen shows, or, when it shows nothing, the server's answer when asked again.
     *
     * Null when that answer does not come. An empty screen is also what a server that did not
     * answer leaves, and that must read as "did not answer", never as "all on this device".
     */
    suspend fun <T> held(shown: List<T>, ask: suspend () -> List<T>): List<T>? =
        shown.ifEmpty { runCatching { ask() }.getOrNull() }

    /** A reading list's entries as chapters, in the server's order, each chapter once. */
    fun chaptersOf(items: List<KavitaReadingListItem>): List<KavitaShelfChapter> =
        items.distinctBy { it.chapterId }.map { item ->
            KavitaShelfChapter(
                chapter = KavitaChapter(
                    id = item.chapterId,
                    title = item.title,
                    pages = item.pagesTotal,
                    pagesRead = item.pagesRead,
                    seriesId = item.seriesId,
                ),
                series = KavitaSeries(
                    id = item.seriesId,
                    name = item.seriesName.orEmpty(),
                    libraryId = item.libraryId,
                ),
                volumeId = item.volumeId,
                bytes = item.fileSize,
            )
        }

    /**
     * Every chapter of a collection's series, or null when any series could not be read.
     *
     * Null rather than the chapters that did arrive: a count stated over part of a collection
     * is a count that is wrong, and the reader is told the server did not answer instead.
     */
    suspend fun chaptersOf(
        series: List<KavitaSeries>,
        volumesOf: suspend (Int) -> List<KavitaVolume>,
    ): List<KavitaShelfChapter>? = coroutineScope {
        val read = series.map { each ->
            async { runCatching { volumesOf(each.id) }.getOrNull()?.let { each to it } }
        }.awaitAll()
        if (read.any { it == null }) return@coroutineScope null
        read.filterNotNull().flatMap { (each, volumes) ->
            volumes.flatMap { volume ->
                volume.chapters.map { chapter ->
                    KavitaShelfChapter(chapter, each, volume.id, chapter.sizeBytes)
                }
            }
        }.distinctBy { it.chapter.id }
    }

    /**
     * What a download would copy, or null when everything is already on the device.
     *
     * [kept] is the chapters this device already holds a download of. A chapter in it is not
     * counted and not queued, so the number stated is the number started.
     */
    fun downloadAsk(chapters: List<KavitaShelfChapter>, kept: Set<Int>): KavitaBulkDownloadAsk? {
        val wanted = chapters.filter { it.chapter.id !in kept }
        if (wanted.isEmpty()) return null
        val stated = wanted.filter { it.bytes > 0 }
        val total = stated.sumOf { it.bytes }
        val size = when {
            stated.isEmpty() -> KavitaBulkSize.Unstated
            stated.size == wanted.size -> KavitaBulkSize.Known(total)
            else -> KavitaBulkSize.AtLeast(total)
        }
        return KavitaBulkDownloadAsk(wanted, size)
    }

    /**
     * Queues every chapter the reader was told about, together.
     *
     * Together rather than one after another: [keep] returns when its file has landed, so
     * one at a time would put one row in the downloads view and hide the other seventy until
     * their turn. The queue bounds how many transfers run at once.
     *
     * @return how many chapters [keep] kept.
     */
    suspend fun download(
        ask: KavitaBulkDownloadAsk,
        keep: suspend (KavitaShelfChapter) -> Boolean,
    ): Int = coroutineScope {
        ask.chapters.map { async { keep(it) } }.awaitAll().count { it }
    }

    /** The chapters a mark would change: those not already in the state asked for. */
    fun changing(chapters: List<KavitaShelfChapter>, read: Boolean): List<KavitaShelfChapter> =
        chapters.filter { it.isFinished != read }

    /**
     * Sends a mark for each of [chapters], one at a time.
     *
     * One at a time and in order: each goes through the one queue every other mark uses, and a
     * server that cannot take the route says so once through [KavitaSync.mark]'s own notice.
     */
    suspend fun mark(
        chapters: List<KavitaShelfChapter>,
        read: Boolean,
        send: suspend (KavitaShelfChapter, Boolean) -> Unit,
    ) {
        for (each in chapters) send(each, read)
    }
}
