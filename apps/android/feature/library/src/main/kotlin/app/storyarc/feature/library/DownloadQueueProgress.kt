package app.storyarc.feature.library

import app.storyarc.core.model.Download
import kotlin.math.roundToInt

/**
 * What a transfer says about itself, over and above its bar.
 *
 * `offline-downloads` asks that a queued publication have "its size shown, and progress
 * visible on the publication and in a single downloads view". The queue row carries only
 * the bar -- a [androidx.compose.material3.LinearProgressIndicator] and nothing beside it,
 * which answers roughly how far and cannot answer how much, the question a reader with
 * little space free is actually asking.
 *
 * A value rather than a formatted string, and here rather than in the composable, for the
 * same two reasons iOS's `DownloadQueueProgress` gives: the rounding rule below is worth
 * pinning in a test on its own, and the *rendering* belongs with the app module because the
 * strings live in its bundle.
 */
object DownloadQueueProgress {

    /** What there is to say, which is not the same for every transfer. */
    sealed interface Statement {
        /** The server stated a total, so the row can state both halves and the percentage. */
        data class Sized(val percent: Int, val downloaded: Long, val expected: Long) : Statement

        /**
         * No total, so no percentage either -- but bytes have landed, and that is a real
         * number. [Download.expectedBytes] is null precisely so a fabricated total is never
         * shown; this is the honest half of the same rule.
         */
        data class Unsized(val downloaded: Long) : Statement
    }

    /**
     * What this transfer's row should say beside its bar, or null when nothing it knows is
     * worth saying.
     *
     * Three transfers get null. One that has failed, because its row already carries a
     * plain-language reason and a percentage under that would compete with the only
     * sentence there a reader has to read. One with neither a total nor a byte through it,
     * because "0 bytes of an unknown total" is a way of writing nothing is known at length.
     * And a finished one, which is not in this list at all.
     */
    fun statement(download: Download): Statement? {
        if (download.state is Download.State.Failed) return null
        if (download.state.isFinished) return null

        val expected = download.expectedBytes
        if (expected != null && expected > 0) {
            return Statement.Sized(
                percent = percent(download),
                downloaded = download.downloadedBytes,
                expected = expected,
            )
        }
        if (download.downloadedBytes <= 0) return null
        return Statement.Unsized(downloaded = download.downloadedBytes)
    }

    /**
     * How far through, as a whole number a person reads off the bar.
     *
     * Derived from [Download.fraction], which already clamps a server that over-reports,
     * rather than dividing a second time.
     *
     * **Rounded to nearest, then held at 99 until every byte is through.** A transfer with
     * 40 kB still to come must not announce itself complete, because a row that reads 100%
     * and then sits there has told the reader the app is stuck.
     */
    private fun percent(download: Download): Int {
        val fraction = download.fraction ?: return 0
        if (fraction >= 1.0) return 100
        return minOf(99, (fraction * 100).roundToInt())
    }
}
