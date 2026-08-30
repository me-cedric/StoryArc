package app.storyarc.feature.library

import app.storyarc.core.model.Publication
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry

/**
 * The library's primary axis: everything, or only what can be read with no network.
 *
 * `library-browsing` makes availability the axis and demotes "one source" to a filter, for
 * a reason worth restating: a scope is a mode a reader can be stuck in, and the old source
 * selector silently narrowed the search as well. Availability cannot strand anyone —
 * whichever half of it is chosen, every publication the app holds is still one tap away.
 *
 * Two values rather than a boolean so the control has something to name in both states.
 */
enum class LibraryAvailability {
    EVERYTHING,
    ON_THIS_DEVICE,
    ;

    val isNarrowing: Boolean get() = this == ON_THIS_DEVICE
}

/**
 * Whether this publication can be opened with no network at all.
 *
 * On Android every row on the shelf is a file: a folder walk found it, a reader imported
 * it, or a download finished and [LibraryViewModel.adoptDownloads] brought it in. So the
 * question is not "are the bytes here" but "may the app still read them", and there is
 * exactly one way the answer is no — a picked folder whose persisted permission the system
 * no longer grants. `LibraryViewModel.folderState` turns that into an unreachable source
 * and, deliberately, leaves its publications on the shelf; a library that shrinks when a
 * card is pulled reads as data loss.
 *
 * A row attributed to a share, a catalogue or a server is on the device whatever that
 * server is doing: it reached the shelf by being downloaded, and a download keeps its
 * source's name so the reader can still see where it came from. Excluding those would hide
 * exactly the publications this axis exists to find.
 */
internal fun Publication.isReadableOffline(registry: SourceRegistry): Boolean {
    // No source at all: the app's own files directory, which is as local as it gets.
    val source = sourceId?.let { registry[it] } ?: return true
    return when (source.kind) {
        SourceKind.LOCAL_FOLDER -> source.state.canFetch
        SourceKind.NETWORK_SHARE, SourceKind.OPDS_CATALOG, SourceKind.KAVITA_SERVER -> true
    }
}

/**
 * The shelf as this axis leaves it.
 *
 * Applied over the view model's already-sorted list rather than inside it, so choosing the
 * axis costs one pass and never a re-sort — and so the order a reader set survives being
 * narrowed and widened again.
 */
internal fun List<Publication>.narrowedTo(
    availability: LibraryAvailability,
    registry: SourceRegistry,
): List<Publication> = when (availability) {
    LibraryAvailability.EVERYTHING -> this
    LibraryAvailability.ON_THIS_DEVICE -> filter { it.isReadableOffline(registry) }
}
