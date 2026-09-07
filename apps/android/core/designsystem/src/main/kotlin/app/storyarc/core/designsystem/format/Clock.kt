package app.storyarc.core.designsystem.format

/**
 * A duration as a listener reads one: `1:02:03`, or `2:03` under an hour.
 *
 * **One formatter, because there were two.** The player wrote its own and the publication
 * page used `DateUtils.formatElapsedTime`, and the two disagreed under an hour — `2:03`
 * against `02:03` — so one chapter read one length on the page and another in the transport.
 * Here rather than in either module, because both draw durations and neither owns the other.
 *
 * **Not the platform's own formatter**, which pads the minutes. The form is a product
 * decision this app has already made twice: the player has always drawn `2:03`, and iOS's
 * `PlaybackClock.time` draws the same. A clock that reads one way on a phone and another way
 * on an iPhone is the drift this file exists to end, and `DateUtils` cannot state that form.
 *
 * A negative duration is clamped to zero. Nothing should produce one, and a clock reading
 * `-1:00` is worse than a clock reading `0:00`.
 */
fun clock(millis: Long): String {
    val total = (millis / 1000).coerceAtLeast(0)
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val seconds = total % 60
    return if (hours > 0) {
        "%d:%02d:%02d".format(hours, minutes, seconds)
    } else {
        "%d:%02d".format(minutes, seconds)
    }
}
