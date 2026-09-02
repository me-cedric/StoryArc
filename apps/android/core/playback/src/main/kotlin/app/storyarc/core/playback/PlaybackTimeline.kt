package app.storyarc.core.playback

/**
 * Which way a skip goes.
 *
 * A type rather than a boolean because the two directions carry different intervals — see
 * [SkipIntervals] — and a `skip(true)` at a call site says nothing about which.
 */
enum class SkipDirection {
    BACK,
    FORWARD,
}

/**
 * Where a skip lands, worked out in whole-book time.
 *
 * `audio-playback`, *Skipping*: "skipping past the start or the end of a chapter continues
 * into the neighbouring one rather than stopping at the boundary". Which is why this
 * converts to a time measured from the start of the publication and back again, rather than
 * clamping inside the current part — **clamping is exactly the boundary stop the spec
 * forbids**, and it is also what the platform does if nothing here intervenes.
 *
 * **Measured rather than assumed, on 2026-09-02.** `PlaybackHost.skip` used to add the
 * interval to the offset, clamp at zero, and say in a comment that "for a folder media3
 * carries the seek into the next item itself". It does not. `BasePlayer.seekToOffset` in
 * `media3-common-1.11.0.aar` reads `min(getCurrentPosition() + offset, getDuration())`, then
 * `max(…, 0)`, then `seekToCurrentItem(…)` — the current *item*, clamped at both of its own
 * ends. So `seekBack()` at five seconds into chapter two lands at the start of chapter two,
 * which is the boundary stop, and the clamp in our own arithmetic did the same thing one
 * layer up. Read out of the shipped bytecode with `javap -c`, not from release notes.
 *
 * **A mirror of iOS's `PlaybackTimeline`**, whose `bookTime(of:)` and `place(atBookTime:)`
 * hold the same three rules: nothing before the start, nothing past the end of the last
 * part, and a part of unknown length is as far as the arithmetic honestly reaches.
 *
 * Every function takes the parts rather than holding them, because the parts change under a
 * source — a chaptered file has one part until the decoder has read its marks — and a
 * timeline that had cached them would answer for the book as it used to be.
 */
object PlaybackTimeline {

    /**
     * How far into the whole publication a position is, or null when it cannot be said.
     *
     * Null when a part *before* this one states no length: treating an unmeasured chapter
     * as zero would put the listener several chapters from where they are, and not moving is
     * better than moving somewhere wrong.
     *
     * Only a [PlaybackDuration.Known] counts. An estimate is for drawing a proportion, and
     * `audio-playback` forbids presenting one as a total — a skip computed through one would
     * land at a place the control did not name.
     */
    fun bookTimeOf(parts: List<PlaybackPart>, position: PlaybackPosition): Long? {
        if (position.partIndex !in parts.indices) return null
        var elapsed = 0L
        for (index in 0 until position.partIndex) {
            elapsed += parts[index].duration.statedMillis ?: return null
        }
        return elapsed + position.offsetMillis
    }

    /**
     * The position a whole-book time names, clamped to the publication's two ends.
     *
     * A listener holding skip-back at the beginning sits at zero rather than being refused
     * or wrapped round to the end; one holding skip-forward at the end sits at the end of
     * the last part, which is where a player that ran out would be sitting anyway.
     */
    fun positionAt(parts: List<PlaybackPart>, bookTimeMillis: Long): PlaybackPosition? {
        if (parts.isEmpty()) return null
        if (bookTimeMillis <= 0) return PlaybackPosition(0, 0)

        var remaining = bookTimeMillis
        for (index in parts.indices) {
            // Nothing after this can be measured, so this is as far as the arithmetic
            // honestly reaches — and it is still inside the book rather than past its end.
            val duration = parts[index].duration.statedMillis
                ?: return PlaybackPosition(index, remaining)
            if (remaining < duration) return PlaybackPosition(index, remaining)
            remaining -= duration
        }
        val last = parts.lastIndex
        return PlaybackPosition(last, parts[last].duration.statedMillis ?: 0L)
    }

    /**
     * Where a skip from [from] by [byMillis] lands. Negative millis go back.
     *
     * Null when the arithmetic cannot be done — a folder whose earlier files the decoder has
     * not measured yet. The caller does nothing with a null, which is the honest answer: the
     * alternative is a clamp, and a clamp is the boundary stop this exists to avoid.
     */
    fun skip(
        parts: List<PlaybackPart>,
        from: PlaybackPosition,
        byMillis: Long,
    ): PlaybackPosition? {
        val elapsed = bookTimeOf(parts, from) ?: return null
        return positionAt(parts, elapsed + byMillis)
    }
}
