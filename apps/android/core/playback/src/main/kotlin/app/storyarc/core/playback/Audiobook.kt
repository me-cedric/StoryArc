package app.storyarc.core.playback

/**
 * A publication to play, and where its audio is.
 *
 * The whole of what the format layer has to hand the player. Deliberately not a
 * `Publication`: `:core:playback` decodes audio and has no business knowing that a library
 * sorts by series, and a service rebuilt after process death has a URI and a title and
 * nothing else. The app assembles one of these from a `Publication` when it starts a book.
 */
data class Audiobook(
    /** The publication's stable id, so a position resolves through content identity. */
    val id: String,
    val title: String,
    val author: String? = null,
    /**
     * The audio, in playing order.
     *
     * One entry for a single file — chaptered or not — and one per file for a folder.
     * `publication-formats` puts a folder's parts in the same natural order that makes a
     * folder of images one comic; the ordering happened in the format layer and this is
     * the result of it, not a second chance to reorder.
     */
    val sources: List<AudioPart>,
    /** Cover art to put on the lock screen, as a URI the platform can fetch. */
    val artworkUri: String? = null,
    /**
     * Parts that were found and cannot be played.
     *
     * `publication-formats`: a damaged audiobook plays "what it can and states how much it
     * could not … in the player's own controls rather than interrupting playback".
     */
    val skippedPartCount: Int = 0,
) {

    /** Whether the parts are separate files or chapter marks inside one. */
    val layout: PartLayout
        get() = if (sources.size > 1) PartLayout.FILES else PartLayout.MARKS

    /** One playable file. */
    data class AudioPart(
        /** Where the bytes are, as a URI string the platform's data source understands. */
        val uri: String,
        /** What a listener is told they are in the middle of, for a folder's parts. */
        val title: String,
    )
}

/**
 * How a publication's parts map onto what the decoder plays.
 *
 * The one thing the player has to branch on, and it is worth a type rather than a boolean
 * because the two cases move the audio in genuinely different ways: choosing a part is a
 * change of item in one and a seek in the other, and a wrong branch is a chapter list
 * whose rows go to the wrong place.
 */
enum class PartLayout {
    /** A folder. Each part is its own item, and the decoder moves between them. */
    FILES,

    /**
     * A single file. Every part is a mark inside one item, so choosing one is a seek and
     * the current part has to be worked out from the position.
     */
    MARKS,
}
