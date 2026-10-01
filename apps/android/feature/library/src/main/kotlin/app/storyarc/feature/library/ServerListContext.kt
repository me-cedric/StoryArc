package app.storyarc.feature.library

import android.content.Context
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaReadingListItem
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.ProgressStore
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Where an entry opened from, when it opened from a server reading list.
 *
 * `collections-and-reading-lists` task 7.3: a server list never joins [Shelves.lists]
 * (`ShelvesStore` keeps only [app.storyarc.core.model.ShelfOrigin.Local]), so
 * [LibraryViewModel.next] cannot see one — it has nothing to walk. This is the app's
 * memory of the one list order a reader is actually inside, carried from
 * [KavitaListScreen]'s own row tap to the reader's end-of-book offer, the way `PlayingBook`
 * carries an audiobook past its own screen.
 */
object ServerListContext {

    /** One server reading list, in the order [KavitaListScreen] showed it. */
    data class Place(
        val serverId: String,
        val serverAddress: KavitaAddress,
        val listId: Int,
        /** The confirmed entries, in display order. A pending entry has none to fetch. */
        val entries: List<KavitaReadingListItem>,
        /** Where in [entries] the reader opened. */
        val position: Int,
    ) {
        val next: KavitaReadingListItem? get() = entries.getOrNull(position + 1)
        val previous: KavitaReadingListItem? get() = entries.getOrNull(position - 1)

        /** Whether [publication] is the entry this place is holding open. */
        fun holds(publication: Publication): Boolean {
            val held = entries.getOrNull(position) ?: return false
            val remote = publication.identity.serverIdentifier ?: return false
            return remote.sourceId.toString() == serverId && remote.remoteId == "chapter:${held.chapterId}"
        }

        /**
         * What the next entry is called, before it is fetched — so the end screen can name
         * it the way [LibraryViewModel.next]'s own answer names a local one.
         */
        fun placeholder(of: KavitaReadingListItem): Publication = Publication(
            identity = PublicationIdentity(
                serverIdentifier = PublicationIdentity.ServerIdentifier(
                    UUID.fromString(serverId),
                    "chapter:${of.chapterId}",
                ),
            ),
            format = PublicationFormat.CBZ,
            displayTitle = of.displayName,
            origin = MetadataOrigin.AUTHORITATIVE,
        )
    }

    private val _current = MutableStateFlow<Place?>(null)
    val current: StateFlow<Place?> = _current.asStateFlow()

    /** Remembered the moment an entry opens from [KavitaListScreen]. */
    fun opened(place: Place) {
        _current.value = place
    }

    /** Forgets the place, so a publication opened some other way is offered nothing. */
    fun clear() {
        _current.value = null
    }

    /**
     * What the reader's end screen offers after [publication], when it is the one
     * [current] is holding open. `null` otherwise — including at the end of the list,
     * which leaves `LibraryViewModel.next`'s own series fallback to answer instead.
     */
    fun next(after: Publication): Publication? =
        current.value?.takeIf { it.holds(after) }?.let { place -> place.next?.let { place.placeholder(it) } }

    /** The mirror of [next], for the chapter-actions "previous" control. */
    fun previous(before: Publication): Publication? =
        current.value?.takeIf { it.holds(before) }?.let { place -> place.previous?.let { place.placeholder(it) } }

    /** What fetching the next or the previous entry found. */
    sealed interface Fetch {
        data class Opened(val publication: Publication, val path: String) : Fetch

        /** [message] is the sentence the failure owes the reader. It names the entry. */
        data class Failed(val message: String) : Fetch
    }

    /**
     * Fetches [item] the way [KavitaListScreen]'s own row does, and advances [current] to it
     * on success — so asking again walks forward rather than refetching the same chapter.
     */
    suspend fun fetch(context: Context, place: Place, item: KavitaReadingListItem): Fetch {
        val opening = fetchEntry(
            context,
            KavitaClient(place.serverAddress),
            item,
            place.serverId,
            KavitaProgressStore.open(context),
        )
        return when (opening) {
            is EntryOpening.Opened -> {
                _current.value = place.copy(position = place.entries.indexOf(item))
                Fetch.Opened(opening.publication, opening.path)
            }
            else -> Fetch.Failed(context.getString(R.string.kavita_open_failed, item.displayName))
        }
    }

    /**
     * Opens the entry an end screen offered, when [offered] is one that [next] or [previous]
     * answered. The fetch is the list screen's own, and so is the seed of the server's
     * position. Null when [offered] names no entry of [current].
     *
     * Tasks 7.3 and 7.14: the offer names a server list's entry before this device has a file
     * for it, so taking the offer fetches one rather than looking for a file that is not there.
     */
    suspend fun open(context: Context, offered: Publication, progress: ProgressStore?): Fetch? {
        val place = current.value ?: return null
        val remote = offered.identity.serverIdentifier ?: return null
        if (remote.sourceId.toString() != place.serverId) return null
        val item = place.entries.firstOrNull { remote.remoteId == "chapter:${it.chapterId}" } ?: return null
        val fetched = fetch(context, place, item)
        if (fetched is Fetch.Opened) seedKavitaOpen(fetched.publication, item.pagesRead, item.pagesTotal, progress)
        return fetched
    }
}

/**
 * What an end-of-publication screen offers after [after]: the next entry of the server list
 * the reader is inside, or else the library's own next.
 *
 * Task 7.14: the library's next can be a Kavita or OPDS row with no file on this device. An
 * end screen cannot open that row, so the offer leaves it out.
 */
fun LibraryViewModel.offeredNext(after: Publication): Publication? =
    ServerListContext.next(after) ?: next(after)?.takeIf { location(it) != null }

/** The mirror of [offeredNext], for the chapter actions' "previous" control. */
fun LibraryViewModel.offeredPrevious(before: Publication): Publication? =
    ServerListContext.previous(before) ?: previous(before)?.takeIf { location(it) != null }
