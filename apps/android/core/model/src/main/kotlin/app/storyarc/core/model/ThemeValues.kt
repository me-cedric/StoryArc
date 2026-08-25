package app.storyarc.core.model

/**
 * The typeface a reader can choose.
 *
 * `reading-themes`: "bundled families plus the publisher's own and the system
 * face". All five bundled families are in `packages/fonts`, subset and declared to
 * the renderer, so every entry here is one the app can actually draw.
 */
enum class ReaderTypeface {
    /** Whatever the publication asks for. The only option under [ThemePreset.ORIGINAL]. */
    PUBLISHER,

    /** The platform's own serif — Noto Serif, New York. Zero bytes. */
    SERIF,

    /** The platform's own sans — Roboto, SF Pro. Zero bytes. */
    SANS,

    /** Designed for screen reading. The default for Paper. */
    LITERATA,

    /** Clean, with a wide weight range. Carries Bold. */
    SOURCE_SERIF,

    /** Classical. Gives Calm a genuinely different voice. */
    EB_GARAMOND,

    /** Slab; holds legibility at small sizes and in Focus's narrow measure. */
    BITTER,

    /** Designed for low vision, and labelled as such wherever it is offered. */
    ATKINSON_HYPERLEGIBLE,

    ;

    /**
     * Whether this face is bundled with the app rather than the platform's.
     *
     * The bundled ones cost binary size and have to be declared to the renderer; the
     * system ones cost nothing and are always available. The picker does not
     * distinguish them, and nothing else needs to either — except the build, which is
     * why `packages/fonts/README.md` states the cost.
     */
    val isBundled: Boolean
        get() = when (this) {
            PUBLISHER, SERIF, SANS -> false
            LITERATA, SOURCE_SERIF, EB_GARAMOND, BITTER, ATKINSON_HYPERLEGIBLE -> true
        }

    /**
     * The family name the renderer matches on.
     *
     * `null` for the publisher's own, which means "override nothing". The two system
     * entries use the generic CSS families so each platform resolves its own face.
     */
    val cssFamily: String?
        get() = when (this) {
            PUBLISHER -> null
            SERIF -> "serif"
            SANS -> "sans-serif"
            LITERATA -> "Literata"
            SOURCE_SERIF -> "Source Serif 4"
            EB_GARAMOND -> "EB Garamond"
            BITTER -> "Bitter"
            ATKINSON_HYPERLEGIBLE -> "Atkinson Hyperlegible"
        }

    /**
     * Whether to say, in the picker, that this face is designed for low vision.
     *
     * `reading-themes`: Atkinson Hyperlegible is "labelled as such in the UI — an
     * accessibility affordance presented as a style option gets missed by the people
     * who need it". So the label is a property of the face rather than a string a
     * sheet remembers to add.
     */
    val isDesignedForLowVision: Boolean get() = this == ATKINSON_HYPERLEGIBLE
}

/**
 * How text is aligned.
 *
 * `reading-themes`: "publisher default, left, justified". Left rather than "start",
 * because the control says left and a reader of a right-to-left book is choosing
 * something the renderer mirrors for them.
 */
enum class ReaderTextAlignment {
    PUBLISHER,
    LEFT,
    JUSTIFIED,
}

/**
 * The discrete font sizes, as a percentage of the publication's own.
 *
 * `reading-themes`: "discrete steps with a visible position indicator, not a free
 * slider", and "at least seven steps from smallest to largest". Nine, weighted
 * upward — the readers who reach for this control are mostly reaching for bigger,
 * and 200% is a real destination while 70% is about as small as body text stays
 * readable.
 */
enum class FontSizeStep(val percent: Int) {
    SMALLEST(70),
    SMALLER(80),
    SMALL(90),
    NORMAL(100),
    LARGE(115),
    LARGER(130),
    LARGEST(150),
    HUGE(175),
    HUGEST(200),

    ;

    /** A fraction for Readium, which takes 1.0 as the publication's own size. */
    val fraction: Double get() = percent / 100.0

    /** Where this step sits on the ladder, for the position indicator. */
    val position: Int get() = entries.indexOf(this)

    val next: FontSizeStep get() = entries[(position + 1).coerceAtMost(entries.lastIndex)]

    val previous: FontSizeStep get() = entries[(position - 1).coerceAtLeast(0)]

    companion object {
        val count: Int get() = entries.size
    }
}

/**
 * Every typographic value a reading theme sets.
 *
 * The numbers live here rather than in each platform's Readium wrapper so the two
 * cannot drift: a preset that reads differently on iOS and Android is the failure
 * mode ADR-0001 accepts everywhere *except* where the two are meant to agree, and a
 * named theme is meant to agree.
 *
 * Each platform maps this onto its own Readium preferences type. Nothing here is a
 * Readium type, which is what lets it be tested on a host JVM.
 */
data class ThemeValues(
    val typeface: ReaderTypeface = ReaderTypeface.PUBLISHER,
    val fontSize: FontSizeStep = FontSizeStep.NORMAL,
    val isBold: Boolean = false,
    /** Multiplier on the publication's line height. 1.0 leaves it alone. */
    val lineHeight: Double = 1.4,
    /** Fractions of an em, the units Readium uses for both. */
    val letterSpacing: Double = 0.0,
    val wordSpacing: Double = 0.0,
    /** Multiplier on the publication's paragraph spacing. */
    val paragraphSpacing: Double = 0.5,
    /** Multiplier on Readium's own page margin. */
    val pageMargins: Double = 1.0,
    val textAlignment: ReaderTextAlignment = ReaderTextAlignment.PUBLISHER,
)

/**
 * The span a slider covers for this axis, where it has one.
 *
 * `null` for the axes that are not sliders — size is a ladder, typeface and
 * alignment are pickers, bold is a toggle. Here rather than in each sheet so the two
 * platforms offer the same range: a line height that reaches 2.5 on one and 2.0 on
 * the other is the kind of difference nobody notices until a reader switches phones.
 */
val ThemeAxis.sliderRange: ClosedFloatingPointRange<Double>?
    get() = when (this) {
        ThemeAxis.FONT_SIZE, ThemeAxis.FONT_FAMILY, ThemeAxis.BOLD_TEXT,
        ThemeAxis.TEXT_ALIGNMENT,
        -> null
        // Below 1.0 the lines collide; above 2.5 a paragraph stops reading as one.
        ThemeAxis.LINE_SPACING -> 1.0..2.5
        // Loose tracking is a legibility aid for some readers and unreadable past a
        // quarter of an em for everyone.
        ThemeAxis.CHARACTER_SPACING -> 0.0..0.25
        ThemeAxis.WORD_SPACING -> 0.0..0.5
        ThemeAxis.PARAGRAPH_SPACING -> 0.0..2.0
        // Half is edge-to-edge; two and a half is the narrow measure Focus wants.
        ThemeAxis.MARGINS -> 0.5..2.5
    }

/** What a slider's number is measured in. */
enum class AxisUnit {
    /** A multiplier of the renderer's own value — "1.5 times". */
    MULTIPLE,

    /** A fraction of the current type size — "0.15 em". */
    EM,
}

/**
 * What an axis's number means, so a screen reader can say it.
 *
 * `native-experience` requires every slider to carry an accessibility value.
 * "0.15" is not a value a reader can act on; "0.15 em" is. The axis answers this
 * for the same reason it answers its own range — one place, so the two platforms
 * cannot describe the same slider differently.
 */
val ThemeAxis.unit: AxisUnit?
    get() = when (this) {
        ThemeAxis.LINE_SPACING, ThemeAxis.MARGINS -> AxisUnit.MULTIPLE
        ThemeAxis.CHARACTER_SPACING, ThemeAxis.WORD_SPACING,
        ThemeAxis.PARAGRAPH_SPACING,
        -> AxisUnit.EM
        ThemeAxis.FONT_SIZE, ThemeAxis.FONT_FAMILY, ThemeAxis.BOLD_TEXT,
        ThemeAxis.TEXT_ALIGNMENT,
        -> null
    }

/**
 * How far one adjustment moves the value.
 *
 * A tenth of the range, rather than a table of five hand-picked numbers that would
 * drift apart. Ten is what makes the ticks Material draws read as a scale rather
 * than as noise, and no reader needs a line height of 1.42.
 *
 * It also stops a drag from submitting a preference change per frame to the
 * renderer, each of which relays out the page.
 */
val ThemeAxis.step: Double?
    get() = sliderRange?.let { (it.endInclusive - it.start) / STEPS_PER_AXIS }

/** Positions on every fine axis. One fewer than this is what Compose calls `steps`. */
const val STEPS_PER_AXIS = 10

/**
 * The value of one axis, for a slider to read.
 *
 * A keyed accessor rather than nine bindings in the sheet: the sheet then draws one
 * slider in a loop, and adding an axis is a branch here instead of a new block of
 * view code.
 */
fun ThemeValues.value(of: ThemeAxis): Double = when (of) {
    ThemeAxis.LINE_SPACING -> lineHeight
    ThemeAxis.CHARACTER_SPACING -> letterSpacing
    ThemeAxis.WORD_SPACING -> wordSpacing
    ThemeAxis.PARAGRAPH_SPACING -> paragraphSpacing
    ThemeAxis.MARGINS -> pageMargins
    ThemeAxis.FONT_SIZE -> fontSize.percent.toDouble()
    ThemeAxis.FONT_FAMILY, ThemeAxis.BOLD_TEXT, ThemeAxis.TEXT_ALIGNMENT -> 0.0
}

/** The same values with one axis moved. */
fun ThemeValues.setting(axis: ThemeAxis, to: Double): ThemeValues = when (axis) {
    ThemeAxis.LINE_SPACING -> copy(lineHeight = to)
    ThemeAxis.CHARACTER_SPACING -> copy(letterSpacing = to)
    ThemeAxis.WORD_SPACING -> copy(wordSpacing = to)
    ThemeAxis.PARAGRAPH_SPACING -> copy(paragraphSpacing = to)
    ThemeAxis.MARGINS -> copy(pageMargins = to)
    // The ladder and the pickers are set directly; a Double cannot express them.
    ThemeAxis.FONT_SIZE, ThemeAxis.FONT_FAMILY, ThemeAxis.BOLD_TEXT,
    ThemeAxis.TEXT_ALIGNMENT,
    -> this
}

/**
 * The preset's own typography.
 *
 * From `design.md`'s preset table. The colours are not here — they are token values
 * under `readingThemes`, so they go through the AAA contrast gate instead of being
 * written down twice.
 */
val ThemePreset.values: ThemeValues
    get() = when (this) {
        // Nothing overridden but size, which is what makes Original Original.
        ThemePreset.ORIGINAL -> ThemeValues()

        // "Soft off-white text on deep neutral, tightened spacing."
        ThemePreset.QUIET -> ThemeValues(
            typeface = ReaderTypeface.SOURCE_SERIF,
            lineHeight = 1.3,
            paragraphSpacing = 0.4,
        )

        // "Book-stock white, serif, comfortable default spacing." Literata, which
        // `design.md` names as Paper's default and which was designed for screens.
        ThemePreset.PAPER -> ThemeValues(
            typeface = ReaderTypeface.LITERATA,
            lineHeight = 1.5,
            paragraphSpacing = 0.6,
        )

        // "Heavier weight, wider spacing. For low vision without leaving the
        // aesthetic." One step up as well: the reader who picks Bold is telling us
        // the default was too small.
        ThemePreset.BOLD -> ThemeValues(
            typeface = ReaderTypeface.SANS,
            fontSize = FontSizeStep.LARGE,
            isBold = true,
            lineHeight = 1.6,
            letterSpacing = 0.02,
            wordSpacing = 0.05,
            paragraphSpacing = 0.8,
        )

        // "Cream-on-brown, generous line height. Long evening sessions." EB
        // Garamond, for the different voice `design.md` asks Calm to have.
        ThemePreset.CALM -> ThemeValues(
            typeface = ReaderTypeface.EB_GARAMOND,
            lineHeight = 1.75,
            paragraphSpacing = 0.8,
            pageMargins = 1.2,
        )

        // "Narrow measure, high contrast, minimal decoration. Fewest words per
        // line." The narrow measure is the wide margin.
        ThemePreset.FOCUS -> ThemeValues(
            typeface = ReaderTypeface.BITTER,
            lineHeight = 1.5,
            paragraphSpacing = 0.5,
            pageMargins = 1.8,
            textAlignment = ReaderTextAlignment.LEFT,
        )
    }
