package app.storyarc

import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackPosition

/**
 * Where the audio is, said the way the rest of the app says where a reader is.
 *
 * The seam between `:core:playback` and `:core:model`, and it lives in the app for the
 * reason `OpenedAudiobook` does: the player knows nothing about a library and the model
 * knows nothing about a decoder, and the app is the one layer entitled to know both exist.
 *
 * **One position, not a second store.** `reading-progress` requires a publication read and
 * listened to to have "one position, and it is wherever the reader last was by either
 * means", so this produces a [ReadingPosition] that goes into the same record as a page
 * index. There is nowhere here for a listening history to accumulate, which is what makes
 * "returning never offers a choice of two places" true by construction.
 */
internal object ListenedPosition {

    /**
     * How close to the end of a part counts as the end of it.
     *
     * The same threshold `EpubReaderViewModel` uses for a reflowable publication, and it is
     * there for the same reason: a decoder's final position is a millisecond count that
     * lands where it lands, and demanding exactly 1.0 would mean a book almost never
     * finished. A comic has no equivalent because its last page is a whole page.
     */
    private const val FINISHED = 0.999

    /**
     * The position to store for where the audio has reached.
     *
     * The part's own length comes from [parts] rather than from the position, because a
     * position is what the player *reports* and a duration is what the container *says* —
     * and where the container says nothing, `PlaybackDuration.Estimated` answers
     * `statedMillis` with null so an estimate is never written down as a measurement.
     */
    fun of(position: PlaybackPosition, parts: List<PlaybackPart>): ReadingPosition =
        ReadingPosition.Listening(
            part = position.partIndex,
            partCount = parts.size,
            offsetMillis = position.offsetMillis,
            ofMillis = parts.getOrNull(position.partIndex)?.duration?.statedMillis,
        )

    /**
     * Whether reaching here finishes the publication.
     *
     * `reading-progress`: finishing by listening is marked "by the same rule that marks a
     * comic finished on its last page" — which for a comic is the last page and for a book
     * of chapters is the end of the last one, not the start of it.
     *
     * A source with no known duration never reaches it, and that is deliberate: its
     * fraction stops at the last part's index over the part count. Claiming the end of a
     * publication from an estimate is exactly what `PlaybackDuration` exists to prevent.
     */
    fun isFinished(position: PlaybackPosition, parts: List<PlaybackPart>): Boolean =
        parts.isNotEmpty() && of(position, parts).fraction >= FINISHED

    /**
     * Where the audio starts, given what the store remembers.
     *
     * Null means the beginning, and it is the answer to three different questions: nothing
     * was recorded, the publication was finished — a listener reopening a book they finished
     * means to hear it, which is the rule the readers already follow — or the one position
     * this publication has was left by *reading* it, which is not somewhere audio can start.
     * Never a prompt: `reading-progress` says returning "never offers a choice of two".
     */
    fun resume(position: ReadingPosition?, isFinished: Boolean): PlaybackPosition? {
        if (isFinished) return null
        val listening = position as? ReadingPosition.Listening ?: return null
        return PlaybackPosition(listening.part, listening.offsetMillis)
    }
}
