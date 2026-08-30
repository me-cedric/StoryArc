package app.storyarc.core.model

/**
 * How hard the system is asking for memory back.
 *
 * Three states rather than a number, because the two platforms report this in different
 * units — Darwin's dispatch source has exactly these three levels, and Android's
 * `onTrimMemory` has seven that collapse onto them. Naming the *state* is what keeps the
 * two readers behaving the same way under the same conditions.
 */
enum class MemoryPressure {
    /** Nothing is wrong; keep the full window. */
    NORMAL,

    /** The system would like memory back. */
    WARNING,

    /** The system is about to start killing processes. */
    CRITICAL,
}

/**
 * How many pages either side of the current one the reader keeps decoded.
 *
 * `comic-reader` asks for two things that pull against each other: "at least the next
 * three and previous one page are decoded and held ready", and "prefetch depth shrinks
 * under memory pressure rather than the app being terminated". The second wins when it
 * applies — a reader that was killed for holding five pages has held nothing at all — and
 * the first is what the window returns to as soon as the pressure lifts.
 *
 * A page of a 2000x3000 scan is about 24 MB decoded, so the difference between the full
 * window and the critical one is roughly a hundred megabytes. That is the size of the
 * decision being made here.
 *
 * iOS's `PrefetchWindow` is the same table.
 *
 * @property ahead pages after the current one.
 * @property behind pages before it.
 */
data class PrefetchWindow(val ahead: Int, val behind: Int) {

    /** The page numbers to hold around a position, clamped to what exists. */
    fun pages(around: Int, of: Int): Set<Int> =
        ((around - behind)..(around + ahead)).filter { it in 0 until of }.toSet()

    companion object {
        /**
         * The spec's floor: three ahead covers a fast run of turns, one behind covers the
         * glance back.
         */
        val FULL = PrefetchWindow(ahead = 3, behind = 1)

        /**
         * What to hold under a given pressure.
         *
         * Warning keeps one page either side, which is still enough for a turn in either
         * direction to be instant. Critical keeps only the page on screen: at that point
         * the system is choosing which process to end, and a reader who waits 200 ms for
         * the next page has lost far less than one whose app disappeared.
         */
        fun under(pressure: MemoryPressure): PrefetchWindow = when (pressure) {
            MemoryPressure.NORMAL -> FULL
            MemoryPressure.WARNING -> PrefetchWindow(ahead = 1, behind = 1)
            MemoryPressure.CRITICAL -> PrefetchWindow(ahead = 0, behind = 0)
        }
    }
}
