package app.storyarc.feature.library

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.model.Publication

/**
 * How many of a shelf's members are already on this device, out of how many it has.
 *
 * `collections-and-reading-lists`' bulk download wants "the item count and total size before
 * starting", and the collection, list and series headers want the same count said the other
 * way round, before the reader ever asks to download anything: how much of this is already
 * here. iOS's `ShelfAvailability` is the same function.
 */
object ShelfAvailability {
    /**
     * Counts the members [onDevice] answers true for, out of the whole set.
     *
     * Takes the predicate rather than a `LibraryViewModel`, so a test can hand it
     * publications of its own choosing without constructing one.
     */
    fun onDeviceCount(members: List<Publication>, onDevice: (Publication) -> Boolean): Pair<Int, Int> =
        members.count(onDevice) to members.size
}

/**
 * The sentence a collection, list or series header states from [ShelfAvailability]'s count.
 *
 * Its own composable, drawn three times over, rather than a `Text` built inline in each
 * header -- the three already disagree about which screen calls them, and a third copy of
 * the interpolation is where that drifts into a third wording.
 */
@Composable
fun ShelfOnDeviceLine(onDevice: Int, total: Int) {
    Text(
        text = stringResource(R.string.shelves_on_device, onDevice, total),
        style = MaterialTheme.typography.bodySmall,
        color = LocalStoryArcPalette.current.textSecondary,
    )
}

/**
 * For a collection or a series, where every member is a publication the library still holds
 * -- `total` is `members.size`.
 */
@Composable
fun ShelfOnDeviceLine(members: List<Publication>, location: (Publication) -> String?) {
    val (onDevice, total) = ShelfAvailability.onDeviceCount(members) { isOnDevice(location(it)) }
    ShelfOnDeviceLine(onDevice, total)
}
