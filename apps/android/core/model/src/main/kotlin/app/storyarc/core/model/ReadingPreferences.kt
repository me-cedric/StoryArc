package app.storyarc.core.model

/** How pages move. See `docs/openspec/specs/comic-reader`. */
enum class PageTransition {
    PAGE_CURL,
    SLIDE,
    FADE,
    VERTICAL_SCROLL,
    HORIZONTAL_SCROLL,
    ;

    /**
     * Reduce Motion replaces the animated transitions with a cross-dissolve.
     * The picker still lists them and says why — `comic-reader` forbids hiding
     * options without an explanation.
     */
    val isAnimatedTransition: Boolean get() = this == PAGE_CURL || this == SLIDE

    fun honoring(reduceMotion: Boolean): PageTransition =
        if (reduceMotion && isAnimatedTransition) FADE else this
}

enum class ReadingDirection {
    LEFT_TO_RIGHT,
    RIGHT_TO_LEFT,
    ;

    companion object {
        /**
         * `publication-formats`: an explicit declaration wins; otherwise
         * Japanese with no declared direction opens right-to-left.
         */
        fun inferred(declared: ReadingDirection?, languageCode: String?): ReadingDirection {
            if (declared != null) return declared
            return if (languageCode?.lowercase()?.startsWith("ja") == true) {
                RIGHT_TO_LEFT
            } else {
                LEFT_TO_RIGHT
            }
        }
    }
}

/**
 * How a page is sized against the screen.
 *
 * `comic-reader`: "fit-to-screen, fit-to-width, fit-to-height, and original size
 * are available, and the choice persists". The four are a *starting* scale, not a
 * replacement for zoom — a reader who pinches from fit-to-width stays zoomed until
 * they pinch back or turn the page.
 */
enum class PageFit {
    /**
     * The whole page on screen. The default, because it is the only mode that never
     * hides part of a panel.
     */
    SCREEN,

    /**
     * Full width, scrolling down. How most people read a comic on a phone: the
     * lettering is legible and the thumb only moves one way.
     */
    WIDTH,

    /** Full height, scrolling across. For a landscape spread on a phone held upright. */
    HEIGHT,

    /** One image pixel to one screen pixel, which is what a scan's own detail looks like. */
    ORIGINAL,

    ;

    /**
     * The scale to start at, given the page as fit-to-screen already sized it.
     *
     * Everything downstream measures zoom against fit-to-screen, so a mode is
     * expressed as a multiple of it rather than as a separate layout. That is what
     * lets pinch, double-tap and the fit control share one number.
     */
    fun scale(
        fittedWidth: Float,
        fittedHeight: Float,
        viewportWidth: Float,
        viewportHeight: Float,
        pixelWidth: Float,
    ): Float {
        if (fittedWidth <= 0f || fittedHeight <= 0f) return 1f
        return when (this) {
            SCREEN -> 1f
            WIDTH -> maxOf(1f, viewportWidth / fittedWidth)
            HEIGHT -> maxOf(1f, viewportHeight / fittedHeight)
            // Never below fit-to-screen: a small scan shown at its own pixels would
            // sit in the middle of the screen looking like a failure to load.
            ORIGINAL -> maxOf(1f, pixelWidth / fittedWidth)
        }
    }
}

enum class ReaderTheme { PAPER, SEPIA, NIGHT, CONTRAST }
