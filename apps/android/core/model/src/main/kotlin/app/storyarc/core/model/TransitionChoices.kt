package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * Which way a continuous scroll runs.
 *
 * Separate from [PageTransition] because `page-transitions` treats it that way: the
 * picker offers four modes, and "the axis is separately overridable".
 */
@Serializable
enum class ScrollAxis {
    VERTICAL,
    HORIZONTAL,
    ;

    companion object {
        /**
         * How much taller than wide a page has to be to read as a strip.
         *
         * A comic page is around 0.65 wide-to-tall and a webtoon panel strip is many
         * times its width. Two is far above the first and far below the second, so it
         * separates them without needing to be tuned.
         */
        const val TALLNESS_THRESHOLD = 2.0

        /**
         * The axis a publication implies.
         *
         * `page-transitions`: "the axis follows the publication's reading direction —
         * vertical for webtoons and reflowable text, horizontal where the publication
         * declares it". A webtoon is one tall strip cut into files; scrolling it
         * sideways is not a preference anyone holds.
         *
         * @param isTall whether the pages are materially taller than they are wide,
         *   which is what `comic-reader` uses to recognise a webtoon that does not say
         *   it is one.
         */
        fun implied(isReflowable: Boolean, isTall: Boolean, declaresHorizontal: Boolean): ScrollAxis =
            when {
                isReflowable || isTall -> VERTICAL
                declaresHorizontal -> HORIZONTAL
                else -> VERTICAL
            }
    }
}

/** Why a transition is offered but cannot run. */
enum class TransitionUnavailability {
    /**
     * The system's reduced-motion setting is on.
     *
     * `page-transitions`: Curl and Slide are replaced by Fast fade, and "the picker
     * still lists them, marked unavailable, with the reason named — a control that
     * vanishes teaches the user nothing".
     */
    REDUCE_MOTION,

    /**
     * The publication's text reflows, and this mode needs a picture of a page.
     *
     * `page-transitions` states the cause itself: "the deforming surface has to be a
     * texture, so each page must be rastered". Until that exists, Curl and Fast fade
     * cannot run over reflowable text — and the spec's "a mode is unavailable for the
     * content" scenario says to *say so* rather than drop the row.
     *
     * A comic pays none of this, which is why the same two modes work there: the page
     * is already a decoded image.
     */
    REFLOWABLE_TEXT,
}

/**
 * Whether this mode animates a *picture* of a page rather than the page itself.
 *
 * Both deform or dissolve a surface, and a surface is a texture. Over a comic that costs
 * nothing, because the page is already an image; over reflowable text the page has to be
 * rastered first.
 */
val PageTransition.needsARasteredPage: Boolean
    get() = this == PageTransition.PAGE_CURL || this == PageTransition.FAST_FADE

/**
 * Whether reflowable text can offer this mode.
 *
 * Fast fade can: it needs one raster, a still of the page that is leaving, and the reader
 * takes that before the navigator moves.
 *
 * Curl cannot yet. It needs the *incoming* page as a second texture before it is on
 * screen. Task 4.3b of `reader-theming-and-page-transitions` owns that, and Apple Books
 * doing it over reflowable text is the evidence that it can be done.
 *
 * **A second offscreen navigator is not what it needs, and this line used to say it was.**
 * Readium keeps the neighbouring pages laid out already — `FadeTurn`'s own note records
 * that `goForward(animated = false)` returns before the next frame here — so the incoming
 * page is reachable by moving the pager under a still of the outgoing one.
 *
 * What is unsettled is the *timing*, not the source. 4.3b records the measurement, and it
 * is iOS that has the expensive half.
 */
val PageTransition.needsTwoRasters: Boolean
    get() = this == PageTransition.PAGE_CURL

/** Whether this is the continuous mode, in either axis. */
val PageTransition.isScroll: Boolean
    get() = this == PageTransition.VERTICAL_SCROLL || this == PageTransition.HORIZONTAL_SCROLL

/** The axis this mode scrolls along, or null for the paged modes. */
val PageTransition.scrollAxis: ScrollAxis?
    get() = when (this) {
        PageTransition.VERTICAL_SCROLL -> ScrollAxis.VERTICAL
        PageTransition.HORIZONTAL_SCROLL -> ScrollAxis.HORIZONTAL
        PageTransition.PAGE_CURL, PageTransition.SLIDE, PageTransition.FAST_FADE -> null
    }

/** The continuous mode along one axis. */
fun scrollAlong(axis: ScrollAxis): PageTransition =
    if (axis == ScrollAxis.VERTICAL) PageTransition.VERTICAL_SCROLL else PageTransition.HORIZONTAL_SCROLL

/**
 * What the transition picker should show, and what actually runs.
 *
 * Two distinct treatments, because the spec asks for two:
 *
 * - Reduced motion leaves Curl and Slide **listed and marked**, because the reader
 *   turned that setting on and can turn it off.
 * - A device that cannot render the curl leaves Curl **absent**, with the reason
 *   stated once — there is nothing the reader can do about it, and a permanently dead
 *   row is furniture.
 *
 * In both cases the stored choice is untouched. `page-transitions` requires that a
 * reader who set Curl on a capable device "reads with Slide without their stored
 * preference being overwritten".
 *
 * @param axis the axis the publication implies. Both scroll rows are offered
 *   regardless — `page-transitions` requires the axis to be "separately overridable",
 *   and two rows are that override with no second control to find. ponytail: two rows,
 *   not a mode plus an axis picker; split them if a third axis ever exists.
 * @param canCurl whether this device can render the curl at the display's refresh
 *   rate. `page-transitions`: "the app never ships a curl that stutters in preference
 *   to a slide that does not".
 */
class TransitionChoices(
    /** What the reader chose. What stays stored. */
    val chosen: PageTransition,
    axis: ScrollAxis,
    reduceMotion: Boolean,
    canCurl: Boolean,
    /**
     * Whether this platform's reader can draw a cross-fade over the content.
     *
     * The same shape as [canCurl], and for the same kind of reason: a capability the
     * platform either has or does not. A comic always can, because the page is already an
     * image. Reflowable text needs the reader to take the turn over from Readium, and the
     * Android EPUB reader does not do that yet — task 4.3b.
     */
    canFade: Boolean = true,
    /**
     * Whether the text reflows. A reflowable page is live web content, so the modes
     * that deform a picture of a page cannot run over it yet — listed with the reason
     * rather than dropped, and only one scroll row, because text scrolls the way it is
     * read.
     */
    isReflowable: Boolean = false,
) {
    /** The rows to draw, in order. */
    /** The axis the publication implies, which is the scroll row shown first. */
    val impliedAxis: ScrollAxis = axis

    val offered: List<PageTransition> = buildList {
        if (canCurl) add(PageTransition.PAGE_CURL)
        add(PageTransition.SLIDE)
        add(PageTransition.FAST_FADE)
        if (isReflowable) {
            // One row, and no axis choice: reflowing text scrolls the way it is read,
            // and a horizontal river of prose is not a preference anyone holds.
            add(PageTransition.VERTICAL_SCROLL)
        } else {
            // The implied axis first, so the row a reader most likely wants is the one
            // nearest the modes above it.
            add(scrollAlong(axis))
            add(
                scrollAlong(
                    if (axis == ScrollAxis.VERTICAL) ScrollAxis.HORIZONTAL else ScrollAxis.VERTICAL,
                ),
            )
        }
    }

    /**
     * Of those rows, the ones that cannot run, and why.
     *
     * Reduced motion is applied second so that it wins where both apply: it is the
     * reader's own setting, and it is the one they can do something about.
     */
    val unavailable: Map<PageTransition, TransitionUnavailability> = buildMap {
        if (isReflowable) {
            // Only the mode that needs *two* rasters, plus the fade where this platform's
            // reader cannot draw one. Fast fade needs a single raster, and the reader takes
            // it before the navigator moves.
            offered.filter { it.needsTwoRasters || (it == PageTransition.FAST_FADE && !canFade) }
                .forEach { put(it, TransitionUnavailability.REFLOWABLE_TEXT) }
        }
        if (reduceMotion) {
            offered.filter { it.isAnimatedTransition }
                .forEach { put(it, TransitionUnavailability.REDUCE_MOTION) }
        }
    }

    /**
     * Whether the curl is missing because this device cannot honour it, which is the
     * one case that needs a sentence outside the list.
     */
    val curlIsAbsent: Boolean = !canCurl

    /**
     * What runs now.
     *
     * Falling back rather than rewriting. Every reason a choice may not run is a
     * condition of the moment: a setting can be turned off, the next device may be able
     * to curl, and the next publication may not reflow.
     */
    val effective: PageTransition = chosen
        .let { if (it == PageTransition.PAGE_CURL && !canCurl) PageTransition.SLIDE else it }
        .honoring(reduceMotion)
        // Content last, and deliberately so. It is the only constraint nothing can work
        // around, so it has to survive the substitutions rather than precede them:
        // reduced motion turns Slide into Fast fade, and over reflowable text Fast fade
        // is itself impossible. Checking content first left `effective` naming a mode
        // this publication refuses.
        .let {
            val refused = it.needsTwoRasters || (it == PageTransition.FAST_FADE && !canFade)
            if (isReflowable && refused) PageTransition.SLIDE else it
        }

    /** Whether a row can be picked. */
    fun isAvailable(mode: PageTransition): Boolean = !unavailable.containsKey(mode)
}
