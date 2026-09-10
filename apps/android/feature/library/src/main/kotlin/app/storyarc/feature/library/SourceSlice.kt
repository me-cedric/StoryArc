package app.storyarc.feature.library

import app.storyarc.core.model.Publication

/**
 * What one source put on the shelf, and whether it holds more than that.
 *
 * **The number the source screen states is a slice, and it used to be stated as a total.**
 * Every contributor reads a bounded first helping — sixty series from a Kavita server, one
 * feed page from a catalogue, two hundred files or forty listings from a share — because a
 * library that walked a whole server before drawing anything would leave a reader looking
 * at nothing. `sources` asks the detail screen for the source's "cached item count", and
 * "cached" is the operative word: a reader whose server holds five thousand titles saw
 * "137 titles" and had no way to tell that from a server that holds 137.
 *
 * So a slice carries the fact. What is done with it is the screen's business — see
 * `sources_detail_partial`, which says *at least* rather than a bare number.
 *
 * [holdsMore] is a *statement about the read*, not about the source: it says the read
 * stopped at its own limit rather than at the end of the source. It can be false for a
 * source that gained a title a second later, and that is correct — nothing here claims to
 * know what the source holds now, only where this read stopped.
 */
internal data class SourceSlice(
    val publications: List<Publication>,
    val holdsMore: Boolean,
) {
    companion object {
        /** A read that reached the end of what the source has. */
        fun whole(publications: List<Publication>) = SourceSlice(publications, holdsMore = false)

        /** Nothing at all, from a source that refused or was not configured. */
        val none = SourceSlice(emptyList(), holdsMore = false)
    }
}
