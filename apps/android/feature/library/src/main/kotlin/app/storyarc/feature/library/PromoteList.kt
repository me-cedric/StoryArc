package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.ListPromotion
import app.storyarc.core.model.ReadingList
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.KavitaProgressStore

/**
 * Putting a reading list a reader made here onto a Kavita server.
 *
 * `collections-and-reading-lists`: when a reader wants a local list on a server "the app
 * offers to copy it, and states which entries cannot be included because they do not exist on
 * that server". Copied, not moved -- the local list is left exactly as it was, because it is
 * the only place the entries the server cannot hold still exist.
 *
 * Nothing is uploaded. This app has no backend and pushes no files anywhere, so "the server
 * has it" means one thing only: the publication was opened from that server, and
 * [KavitaProgressStore] wrote down which chapter it was. That note is what the copy sends,
 * and its absence is why an entry is left behind.
 *
 * Extensions rather than more of [LibraryViewModel], which is long enough. iOS keeps the same
 * three calls in `PromoteList.swift`.
 */

/**
 * What copying this list onto this server would move, and what it would leave behind.
 *
 * Worked out before anything happens and shown to the reader, then used again to decide what
 * is actually sent. One answer, so the screen cannot promise a different copy from the one
 * that runs.
 */
fun promotionOf(
    list: ReadingList,
    server: KavitaPage,
    kavita: KavitaProgressStore?,
): ListPromotion = ListPromotion.of(list.entries) { entry ->
    kavita?.origin(entry)?.sourceId == server.id
}

/**
 * Copies a local reading list onto a server, in the list's own order.
 *
 * Answers with what the reader can undo, or null when nothing reached the server. The entries
 * go one at a time rather than grouped by series: Kavita appends in the order it is asked,
 * and grouping would rearrange a crossover into series order -- which is the one thing a
 * reading list exists to prevent.
 */
suspend fun promote(
    list: ReadingList,
    server: KavitaPage,
    kavita: KavitaProgressStore?,
): BulkUndo? {
    val plan = promotionOf(list, server, kavita)
    if (!plan.isPossible) return null

    val client = KavitaClient(server.address)
    val made = runCatching { client.createList(list.name) }.getOrNull() ?: return null

    val copied = mutableSetOf<String>()
    for (entry in plan.copying) {
        val origin = kavita?.origin(entry) ?: continue
        runCatching {
            client.append(made.id, origin.seriesId, listOf(origin.chapterId))
        }.onSuccess { copied += entry }
    }

    // The server went away between the plan and the copy. Leaving an empty list behind would
    // put something on the server that nobody asked for and nobody can explain.
    if (copied.isEmpty()) {
        runCatching { client.deleteList(made.id) }
        return null
    }

    return BulkUndo(BulkUndo.Kind.Promoted(server.id, made.id), copied)
}

/**
 * Takes a copied list back off the server, within its ten seconds.
 *
 * The key is read here rather than held in the undo record: a record waiting out its window
 * is view state, and view state is not where a secret belongs.
 */
suspend fun LibraryViewModel.withdrawList(
    sourceId: String,
    listId: Int,
    credentials: CredentialStore?,
) {
    val address = registry.value.sources
        .firstOrNull { it.id.toString() == sourceId }
        ?.let { KavitaPage.of(it, credentials)?.address }
        ?: return
    runCatching { KavitaClient(address).deleteList(listId) }
}

/**
 * What a copy needs from the app layer, which owns the secrets a server asks for.
 *
 * One value rather than three callbacks threaded through two screens: the shelf menu takes it
 * or it does not, and a screen wired without one simply does not offer the action.
 */
data class ListPromoter(
    val plan: (ReadingList, KavitaPage) -> ListPromotion,
    val copy: suspend (ReadingList, KavitaPage) -> BulkUndo?,
    val withdraw: suspend (String, Int) -> Unit,
)
