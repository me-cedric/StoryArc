package app.storyarc.feature.library

import android.graphics.Bitmap
import app.storyarc.core.model.RememberedShelf

/**
 * What a Kavita shelf's card draws on the home surface, decided from what the server
 * answered.
 *
 * The owner's field report on v0.1.1: "Kavita collections and reading lists on Home show only
 * a title, no cover." [HomeShelfSummary.tiles] is empty for every remembered server shelf --
 * [HomeShelfIndex.assemble] never reaches a source, by `home-screen`'s own rule -- so nothing
 * had ever asked a server for this card's artwork at all. This is the order the field
 * report's own decision states: the server's own cover, then the first members', then a
 * named blank.
 *
 * Pure, so the branch a fetch cannot force a test into can be asserted directly -- the same
 * line the existing `ServerShelfTilesTest`-equivalent tests already draw for the Shelves
 * screen: the routing and the tile selection are tested, the coroutine that fetches is not.
 * iOS's `HomeShelfCoverPlan` is the same three cases.
 */
sealed class HomeShelfCoverPlan {
    /** The server's own locked cover, drawn whole. */
    object Sole : HomeShelfCoverPlan()

    /** The first members, composited the way a local shelf's are. */
    data class Composite(val ids: List<String>) : HomeShelfCoverPlan()

    /** Nothing answered: no locked cover and no member drew one either. */
    object Blank : HomeShelfCoverPlan()

    companion object {
        fun decide(hasLockedCover: Boolean, memberIds: List<String>): HomeShelfCoverPlan = when {
            hasLockedCover -> Sole
            memberIds.isNotEmpty() -> Composite(memberIds)
            else -> Blank
        }
    }
}

/**
 * What fetching a server shelf's artwork found: the plan, and whichever covers it decoded.
 *
 * The plan alone is not enough to draw with -- [ShelfComposite] wants the bitmaps keyed by
 * the same ids the plan names -- so the two travel together rather than as two states a
 * composable could observe out of step with each other.
 */
data class HomeShelfArtworkOutcome(
    val plan: HomeShelfCoverPlan,
    val covers: Map<String, Bitmap> = emptyMap(),
    /**
     * The shelf with the count and the finished position the same fetch found, or null when
     * the server did not answer. The card draws it at once.
     */
    val counted: RememberedShelf? = null,
)

/**
 * The one key [HomeShelfCoverPlan.Sole] draws, in the covers map [HomeShelfArtworkOutcome]
 * carries.
 *
 * Public rather than internal: the app layer builds this map (`HomeDestination`, in `:app`),
 * because it is the one part of the app that is allowed to reach the source the shelf came
 * from -- this module's own composable only draws what it is handed.
 */
const val HOME_SHELF_SOLE_COVER_KEY = "sole-cover"
