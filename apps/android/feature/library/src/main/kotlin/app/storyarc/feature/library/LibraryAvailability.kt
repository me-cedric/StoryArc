package app.storyarc.feature.library

import app.storyarc.core.model.MatchGroup
import app.storyarc.core.model.Publication
import app.storyarc.core.model.Source
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

    companion object {
        /**
         * The name `LibraryPreferences` wrote down, turned back into an axis.
         *
         * The widest answer for anything it cannot read — never chosen, or a name this
         * version of the app no longer has. Widening is the safe direction: it shows a
         * reader more of their library than they asked for, where the other mistake hides
         * publications behind a narrowing nobody set.
         */
        fun named(name: String?): LibraryAvailability =
            entries.firstOrNull { it.name == name } ?: EVERYTHING
    }
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

/**
 * The libraries a search at this scope puts the question to.
 *
 * **This is the half a row filter would miss**, and it is a requirement rather than an
 * optimisation. `library-browsing`: narrowing to what is on the device "removes that notice,
 * *because nothing is then being waited for*". A scope that only hid rows would leave the
 * fan-out running and the could-not-answer line up, so the reader who narrowed precisely to
 * stop waiting would still be waiting.
 *
 * [RemoteSearch.answers] still decides who *can* be asked at all — a folder and an SMB share
 * have no search endpoint at either scope. This decides who *is*. iOS's
 * `LibraryAvailability.sourcesToAsk` reaches the same two lines from the same clause.
 */
internal fun LibraryAvailability.sourcesToAsk(registry: SourceRegistry): List<Source> =
    when (this) {
        LibraryAvailability.EVERYTHING -> registry.sources.filter(RemoteSearch::answers)
        LibraryAvailability.ON_THIS_DEVICE -> emptyList()
    }

/**
 * Match groups, narrowed to a search scope.
 *
 * An extension on the list rather than a member of the axis, exactly as the shelf's own
 * [narrowedTo] is: what is being narrowed is the *listing*, and the scope is the argument.
 *
 * A group left empty is **dropped**, not kept with nothing in it. `library-browsing` groups
 * results by match kind, and a heading over no rows would tell the reader their term matched
 * a series — when what it matched is a series they cannot open on a plane.
 *
 * One Kotlin name for one idea, and a second JVM name because the two receivers erase to the
 * same `List`. Renaming one of them in Kotlin would be the platform's limitation leaking into
 * the vocabulary the screen is written in.
 */
@JvmName("matchGroupsNarrowedTo")
internal fun List<MatchGroup>.narrowedTo(
    availability: LibraryAvailability,
    registry: SourceRegistry,
): List<MatchGroup> = when (availability) {
    LibraryAvailability.EVERYTHING -> this
    LibraryAvailability.ON_THIS_DEVICE -> mapNotNull { group ->
        val kept = group.publications.narrowedTo(availability, registry)
        if (kept.isEmpty()) null else group.copy(publications = kept)
    }
}
