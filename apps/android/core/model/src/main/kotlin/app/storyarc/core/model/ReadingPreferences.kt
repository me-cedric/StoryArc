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

enum class PageFit { SCREEN, WIDTH, HEIGHT, ORIGINAL }

enum class ReaderTheme { PAPER, SEPIA, NIGHT, CONTRAST }
