package app.storyarc.feature.library

/**
 * Which badge a local reading list's row stands behind.
 *
 * `collections-and-reading-lists`' delta: "each entry states its own read state -- finished,
 * part-read with the position reached, or unread -- in the same terms the library uses for a
 * publication". A value rather than a formatted string, so [readingListRowBadge] stays free
 * of `stringResource` and callable from a test with no Compose context -- the same reason
 * `ServerShelfArtwork` is a value and not a view. The composable resolves the actual words,
 * and reaches `library.readState.unread` for [None] only when it speaks the row out loud: an
 * unread entry draws nothing, the rule the library's own grid cell and
 * `KavitaShelfScreens.kt`'s server row both already keep. iOS's `ReadingListRowState` makes
 * the same three-way split.
 */
internal sealed class ReadingListRowBadge {
    /** Nothing known to say -- an unread entry, or one the source no longer has.*/
    object None : ReadingListRowBadge()
    object Finished : ReadingListRowBadge()
    data class PartRead(val percent: Int) : ReadingListRowBadge()
}

internal fun readingListRowBadge(isFinished: Boolean, percentRead: Int?): ReadingListRowBadge =
    when {
        isFinished -> ReadingListRowBadge.Finished
        percentRead != null -> ReadingListRowBadge.PartRead(percentRead)
        else -> ReadingListRowBadge.None
    }
