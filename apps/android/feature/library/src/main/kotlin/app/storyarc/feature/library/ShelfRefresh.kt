package app.storyarc.feature.library

import app.storyarc.core.model.LibraryScope
import app.storyarc.core.model.SourceProbe
import app.storyarc.core.model.SourceRegistry

/**
 * What one pull re-fetches: the sources the shelf is showing, and no others.
 *
 * `sources`' *Refreshing a source* asks a pull to "re-fetch the catalogue in the background"
 * and to update the view "incrementally rather than clearing it". It does not ask a pull on
 * one shelf to re-fetch the whole library, and both platforms did one of the two wrong things:
 * this pull walked the folders and asked no server at all, so a reader looking at a server's
 * shelf got nothing new; iOS asked every server *and* walked every folder on every pull, so a
 * reader on a metered link paid for the whole library because they pulled one shelf.
 *
 * **A folder walk is local disk and costs no data**, so it runs whenever the shelf could be
 * showing a folder's publications — including a library with no folder source at all, because
 * the managed import folder belongs to no source and is walked on every scan. **The network is
 * asked only when the shelf is showing something reached over one.**
 *
 * Pure, and its own type, for the reason [SourceProbe] is: the decision is what a test can
 * reach, and a decision written inside a composable is a decision nothing can assert. iOS's
 * `ShelfRefresh` holds the same table.
 *
 * ponytail: the network half is all-or-nothing. A shelf narrowed to one server asks *every*
 * server, because the probe needs the credentials and the pinned certificates and those are
 * the app layer's — `LibraryScreen` is handed one `onProbeSources` lambda and no way to name a
 * source. That is the whole remaining cost, and it is bounded by the number of servers a
 * reader configured. Scoping it further means a new callback through `AppDestinations`.
 *
 * ponytail: the same lambda reports no progress, so `PullToRefreshBox` follows the folder
 * walk and a shelf narrowed to one server refreshes without a sustained indicator. Driving it
 * from the sources' own `Connecting` state instead would blink it on every background probe,
 * which is worse. What it needs is a signal that tells a pull from the backoff loop.
 */
data class ShelfRefresh(
    /** Whether the folders are walked again. */
    val walksFolders: Boolean,
    /** Whether the sources that are reached over a network are asked again. */
    val asksNetwork: Boolean,
) {
    companion object {
        /**
         * What a pull on this shelf should re-fetch.
         *
         * A scope naming a source that has gone is every source, which is
         * [LibraryScope.resolved]'s own answer: a stored scope pointing at a source removed
         * last session must not turn a pull into nothing at all.
         */
        fun of(scope: LibraryScope, registry: SourceRegistry): ShelfRefresh {
            val one = scope.resolved(registry).sourceId?.let { registry[it] }
                ?: return ShelfRefresh(
                    walksFolders = true,
                    asksNetwork = registry.sources.any { SourceProbe.isRemote(it.kind) },
                )
            val isRemote = SourceProbe.isRemote(one.kind)
            return ShelfRefresh(walksFolders = !isRemote, asksNetwork = isRemote)
        }
    }
}
