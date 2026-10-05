package app.storyarc.feature.epubreader

import app.storyarc.core.model.TotalProgression
import app.storyarc.core.playback.PlaybackPart
import org.readium.r2.shared.publication.Link

/**
 * A publication's reading order, as the player's chapter list.
 *
 * `audio-playback`, *Chapters*: "a publication with no chapter markers lists its parts in
 * playing order instead, rather than showing an empty list". A reflowable EPUB has no
 * chapter marks at all — it has resources — so the reading order **is** the part list, and
 * the table of contents is what names the rows.
 *
 * **One part per reading-order resource, never one per table-of-contents entry.** A table
 * of contents may point several entries at anchors inside one resource, and may skip
 * resources altogether. The voice walks resources, so a list built from the contents would
 * mark a chapter the voice is not in and would leave the reader's place unnamed.
 *
 * **A resource the contents do not name carries no title, rather than a made-up one.** The
 * word for an unnamed chapter is a word, and the catalogue holding it belongs to the
 * surface that draws the list — see `PlayerScreen`. iOS splits it at the same seam:
 * `SpokenParts` leaves the title nil and `PlayerLabels.chapter` answers with a number.
 *
 * No part states a duration. A synthesised chapter's length is a guess from a character
 * count that moves the moment the listener changes the speed, and `audio-playback` forbids
 * stating a total that was invented — which is what keeps the scrub control, the clock and
 * *end of chapter* off a read-aloud session without anything asking what is speaking.
 */
internal object SpokenParts {

    /**
     * @param readingOrder the publication's reading order, by href, in playing order.
     * @param titledBy the table of contents as href-to-title pairs, in the order the
     *   contents declare them: the first entry to name a resource is the one that names it,
     *   because a contents list goes from the top of a chapter downwards.
     */
    fun of(readingOrder: List<String>, titledBy: List<Pair<String, String>>): List<PlaybackPart> {
        val named = mutableMapOf<String, String>()
        for ((href, title) in titledBy) {
            val name = title.trim()
            // An entry pointing inside a resource names a place in a chapter rather than the
            // chapter, so it never wins the row. iOS's `SpokenParts` drops the same entries.
            if (name.isEmpty() || href.contains('#')) continue
            named.putIfAbsent(TotalProgression.withoutFragment(href), name)
        }
        return readingOrder.map {
            PlaybackPart(title = named[TotalProgression.withoutFragment(it)].orEmpty())
        }
    }

    /**
     * A table of contents, flattened to href-and-title pairs in declared order.
     *
     * Depth first, because that is the order a reader reads the contents in, and [of]
     * answers with the first entry that names a resource.
     */
    fun titles(contents: List<Link>): List<Pair<String, String>> =
        contents.flatMap { link ->
            listOf(link.href.toString() to link.title.orEmpty()) + titles(link.children)
        }
}
