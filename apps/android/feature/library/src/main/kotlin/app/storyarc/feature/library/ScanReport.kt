package app.storyarc.feature.library

import app.storyarc.core.format.ScanEvent

/**
 * What the library is doing, so the UI can say so rather than guess.
 *
 * Moved here from `LibraryViewModel.kt`, which sits on the 800-line ratchet
 * `scripts/line-cap.mjs` records and therefore cannot grow. The seam is real either way:
 * this file is what a scan *reports*, and the view model is what runs one.
 */
sealed interface LibraryScanState {
    data object Idle : LibraryScanState

    /** A scan is running. The count is what `local-library` asks to be reported. */
    data class Scanning(val found: Int) : LibraryScanState

    data class Finished(val found: Int, val skipped: Int) : LibraryScanState
}

/**
 * The publications a scan could not open, and whether the reader has been told about them.
 *
 * `library-browsing`'s *What could not be opened*: the library "SHALL say **which**
 * publications it could not open, not how many, and SHALL let a reader reach the reason".
 *
 * **Nothing new is produced here.** `LibraryScanner` has always emitted the pair —
 * `ScanEvent.Skipped(path, reason)`, with the reason `publication-formats` words for that
 * refusal — and `rescan` matched `is ScanEvent.Skipped -> Unit`, so a walk that met a 7-Zip
 * container and a password-protected archive reported "2 couldn't be opened" and lost both
 * sentences. This is the thing that keeps them.
 *
 * A value type with no composable in it, because every decision here is a rule rather than a
 * layout: whether a notice appears at all, whether it names a publication or a count,
 * whether a set the reader has already dismissed comes back, and when an entry leaves. The
 * count it replaces needed none of those, which is why it had no test.
 *
 * iOS's `SkippedPublications` is the same type, asserted case for case.
 */
data class SkippedPublications(
    /** What could not be opened, in the order the walk met it. */
    val entries: List<Entry> = emptyList(),
    /**
     * The names the reader has already been shown and dismissed.
     *
     * Names rather than a single flag, which is what makes the *unless the set changes* half
     * of the spec work: a scan that meets one new failure among four old ones has something
     * to say, and a scan that meets the same four does not.
     */
    private val acknowledged: Set<String> = emptySet(),
) {
    /**
     * One publication and the reason `publication-formats` gives for refusing it.
     *
     * The name is the document's own name, which is all a publication that could not be
     * indexed has — there is no metadata to read a title out of, because reading it is the
     * thing that failed. It is still the name the reader sees in their own file browser,
     * which is what makes it actionable.
     */
    data class Entry(
        val name: String,
        /**
         * Verbatim from the scanner. Deliberately not re-worded here: a second sentence for
         * the same condition is a second thing to keep true.
         */
        val reason: String,
    )

    /**
     * What the library has to say about this, if anything.
     *
     * Four cases and not a boolean plus a count, because the four are genuinely different
     * sentences and the delta spec gives each of them its own scenario. A composable that
     * switched on `entries.size` alone could not tell [Reachable] from [Several].
     */
    sealed interface Notice {
        /** Nothing failed, or everything that had failed now opens. */
        data object Nothing : Notice

        /** Exactly one, named, with its reason stated where the notice is. */
        data class One(val name: String, val reason: String) : Notice

        /** More than one. The count is here and the reasons are in the list. */
        data class Several(val count: Int) : Notice

        /**
         * The reader dismissed it, and the list is still reachable.
         *
         * Not [Nothing]: the entries are still there and the way to them has to be too, "so
         * a reader who dismissed it in the middle of something can come back to it".
         */
        data object Reachable : Notice
    }

    val notice: Notice
        get() = when {
            entries.isEmpty() -> Notice.Nothing
            entries.none { it.name !in acknowledged } -> Notice.Reachable
            entries.size == 1 -> entries.first().let { Notice.One(it.name, it.reason) }
            else -> Notice.Several(entries.size)
        }

    /**
     * What a finished scan makes of this, replacing what the one before it made.
     *
     * Replacing rather than accumulating, and that single choice is what delivers three of
     * the delta spec's scenarios at once:
     *
     * - *A publication that later opens* leaves without being dismissed, because a walk that
     *   opened it does not report it, and a walk is the only thing that writes here.
     * - A file the reader **deleted** leaves the same way. Nothing else would remove it, and
     *   a list that keeps naming files that are gone is the graveyard the notice exists to
     *   avoid becoming.
     * - *The count is not shown again for the same publications* falls out of keeping the
     *   acknowledgements that still have an entry and dropping the ones that do not — so a
     *   publication that is fixed and then breaks again is news a second time.
     *
     * @param met every refusal of one complete scan, in the order it met them. A caller
     *   accumulates these across the several trees one scan walks and settles once, so a
     *   reader watching a two-folder scan does not see the first folder's notice replaced
     *   halfway.
     */
    fun settling(met: List<Entry>): SkippedPublications {
        // The same document can be met twice — a tree walked under two sources. First wins,
        // so the order is the walk's.
        val settled = met.distinctBy { it.name }
        return SkippedPublications(
            entries = settled,
            acknowledged = acknowledged intersect settled.map { it.name }.toSet(),
        )
    }

    /** The reader put it away. The list stays. */
    fun dismissing(): SkippedPublications =
        copy(acknowledged = entries.map { it.name }.toSet())
}

/**
 * The refusal a scan event carries, as an entry.
 *
 * **`rescan` used to keep a `var skipped = 0` beside this and nothing else.** One
 * `ScanEvent.Skipped` is one skipped file — `LibraryScanner` returns `Tally(skipped = 1)` on
 * exactly the paths that emit one — so the count `LibraryScanState.Finished` carries is the
 * size of the list of pairs, and the parallel counter was a second source of truth for the
 * same fact with less information in it.
 */
internal fun ScanEvent.Skipped.asRefusal() = SkippedPublications.Entry(path, reason)
