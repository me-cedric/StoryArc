package app.storyarc.core.model

/**
 * Whether a device has proved it cannot draw the curl, from the turns it has already drawn.
 *
 * `page-transitions` says Curl is absent where the device "cannot render it at the display's
 * refresh rate", and that "the app never ships a curl that stutters in preference to a slide
 * that does not". Nothing had ever measured that, so no device had ever withheld Curl for the
 * refresh rate -- only [canCurlOn]'s API floor did, which is a different sentence about a
 * different capability.
 *
 * **D11 is the measurement.** The first [TURNS] curls on a device are counted, and the median
 * of what they cost decides. A median rather than a mean, because the first curl of a session
 * pays for a cold shader cache and a scheduler that has not seen this work before: a mean lets
 * that one turn condemn a phone that draws every later turn perfectly.
 *
 * iOS's `CurlVerdict` holds the same two numbers.
 */
object CurlVerdict {

    /** How many curls a device draws before it is judged. */
    const val TURNS = 3

    /**
     * How much longer than the display's own interval a frame may take.
     *
     * One frame in three missed, which on a 60 Hz panel is a mean frame time near 25 ms.
     * Below it a reader sees a curl that keeps up with the finger; above it they see the
     * stutter `page-transitions` refuses to ship.
     */
    const val TOLERANCE = 1.5

    /**
     * Whether the device has proved it cannot curl, or null while it is still being asked.
     *
     * Null and false are deliberately different answers. A device is given the curl until it
     * fails, never withheld while the question is open.
     */
    fun cannotCurl(strains: List<Double>): Boolean? {
        if (strains.size < TURNS) return null
        return strains.take(TURNS).sorted()[TURNS / 2] > TOLERANCE
    }
}
