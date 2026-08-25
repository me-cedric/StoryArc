public import Foundation

/// The typeface a reader can choose.
///
/// `reading-themes`: "bundled families plus the publisher's own and the system
/// face". All five bundled families are in `packages/fonts`, subset and declared to
/// the renderer, so every entry here is one the app can actually draw.
public enum ReaderTypeface: String, Sendable, Codable, CaseIterable {
    /// Whatever the publication asks for. The only option under `original`.
    case publisher
    /// The platform's own serif — New York, Noto Serif. Zero bytes.
    case serif
    /// The platform's own sans — SF Pro, Roboto. Zero bytes.
    case sans
    /// Designed for screen reading. The default for Paper.
    case literata
    /// Clean, with a wide weight range. Carries Bold.
    case sourceSerif
    /// Classical. Gives Calm a genuinely different voice.
    case ebGaramond
    /// Slab; holds legibility at small sizes and in Focus's narrow measure.
    case bitter
    /// Designed for low vision, and labelled as such wherever it is offered.
    case atkinsonHyperlegible
}

public extension ReaderTypeface {
    /// Whether this face is bundled with the app rather than the platform's.
    ///
    /// The bundled ones cost binary size and have to be declared to the renderer;
    /// the system ones cost nothing and are always available. The picker does not
    /// distinguish them, and nothing else needs to either — except the build, which
    /// is why `packages/fonts/README.md` states the cost.
    var isBundled: Bool {
        switch self {
        case .publisher, .serif, .sans: false
        case .literata, .sourceSerif, .ebGaramond, .bitter, .atkinsonHyperlegible: true
        }
    }

    /// The family name the renderer matches on.
    ///
    /// `nil` for the publisher's own, which means "override nothing". The two system
    /// entries use the generic CSS families so each platform resolves its own face —
    /// New York and SF Pro on iOS, Noto Serif and Roboto on Android.
    var cssFamily: String? {
        switch self {
        case .publisher: nil
        case .serif: "serif"
        case .sans: "sans-serif"
        case .literata: "Literata"
        case .sourceSerif: "Source Serif 4"
        case .ebGaramond: "EB Garamond"
        case .bitter: "Bitter"
        case .atkinsonHyperlegible: "Atkinson Hyperlegible"
        }
    }

    /// Whether to say, in the picker, that this face is designed for low vision.
    ///
    /// `reading-themes`: Atkinson Hyperlegible is "labelled as such in the UI — an
    /// accessibility affordance presented as a style option gets missed by the
    /// people who need it". So the label is a property of the face rather than a
    /// string a sheet remembers to add.
    var isDesignedForLowVision: Bool { self == .atkinsonHyperlegible }
}

/// How text is aligned.
///
/// `reading-themes`: "publisher default, left, justified". Left rather than
/// "start", because the control says left and a reader of a right-to-left book is
/// choosing something the renderer mirrors for them.
public enum ReaderTextAlignment: String, Sendable, Codable, CaseIterable {
    case publisher
    case left
    case justified
}

/// The discrete font sizes, as a percentage of the publication's own.
///
/// `reading-themes`: "discrete steps with a visible position indicator, not a free
/// slider", and "at least seven steps from smallest to largest". Nine, weighted
/// upward — the readers who reach for this control are mostly reaching for bigger,
/// and 200% is a real destination while 70% is about as small as body text stays
/// readable.
public enum FontSizeStep: Int, Sendable, Codable, CaseIterable, Comparable {
    case smallest = 70
    case smaller = 80
    case small = 90
    case normal = 100
    case large = 115
    case larger = 130
    case largest = 150
    case huge = 175
    case hugest = 200

    /// A fraction for Readium, which takes 1.0 as the publication's own size.
    public var fraction: Double { Double(rawValue) / 100 }

    /// Where this step sits on the ladder, for the position indicator.
    public var position: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static var count: Int { allCases.count }

    public var next: FontSizeStep {
        let all = Self.allCases
        return all[min(position + 1, all.count - 1)]
    }

    public var previous: FontSizeStep {
        Self.allCases[max(position - 1, 0)]
    }

    public static func < (lhs: FontSizeStep, rhs: FontSizeStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Every typographic value a reading theme sets.
///
/// The numbers live here rather than in each platform's Readium wrapper so the two
/// cannot drift: a preset that reads differently on iOS and Android is the failure
/// mode ADR-0001 accepts everywhere *except* where the two are meant to agree, and
/// a named theme is meant to agree.
///
/// Each platform maps this onto its own Readium preferences type. Nothing here is
/// a Readium type, which is what lets it be tested on a host.
public struct ThemeValues: Sendable, Equatable, Codable {
    public var typeface: ReaderTypeface
    public var fontSize: FontSizeStep
    public var isBold: Bool
    /// Multiplier on the publication's line height. 1.0 leaves it alone.
    public var lineHeight: Double
    /// Fractions of an em, the units Readium uses for both.
    public var letterSpacing: Double
    public var wordSpacing: Double
    /// Multiplier on the publication's paragraph spacing.
    public var paragraphSpacing: Double
    /// Multiplier on Readium's own page margin.
    public var pageMargins: Double
    public var textAlignment: ReaderTextAlignment

    public init(
        typeface: ReaderTypeface = .publisher,
        fontSize: FontSizeStep = .normal,
        isBold: Bool = false,
        lineHeight: Double = 1.4,
        letterSpacing: Double = 0,
        wordSpacing: Double = 0,
        paragraphSpacing: Double = 0.5,
        pageMargins: Double = 1,
        textAlignment: ReaderTextAlignment = .publisher
    ) {
        self.typeface = typeface
        self.fontSize = fontSize
        self.isBold = isBold
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.wordSpacing = wordSpacing
        self.paragraphSpacing = paragraphSpacing
        self.pageMargins = pageMargins
        self.textAlignment = textAlignment
    }
}

public extension ThemeAxis {
    /// The span a slider covers for this axis, where it has one.
    ///
    /// `nil` for the axes that are not sliders — size is a ladder, typeface and
    /// alignment are pickers, bold is a toggle. Here rather than in each sheet so
    /// the two platforms offer the same range: a line height that reaches 2.5 on one
    /// and 2.0 on the other is the kind of difference nobody notices until a reader
    /// switches phones.
    var sliderRange: ClosedRange<Double>? {
        switch self {
        case .fontSize, .fontFamily, .boldText, .textAlignment: nil
        // Below 1.0 the lines collide; above 2.5 a paragraph stops reading as one.
        case .lineSpacing: 1.0...2.5
        // Loose tracking is a legibility aid for some readers and unreadable past a
        // quarter of an em for everyone.
        case .characterSpacing: 0...0.25
        case .wordSpacing: 0...0.5
        case .paragraphSpacing: 0...2.0
        // Half is edge-to-edge; two and a half is the narrow measure Focus wants.
        case .margins: 0.5...2.5
        }
    }

    /// What an axis's number means, so a screen reader can say it.
    ///
    /// `native-experience` requires every slider to carry an accessibility value.
    /// "0.15" is not a value a reader can act on; "0.15 em" is. The axis answers
    /// this for the same reason it answers its own range — one place, so the two
    /// platforms cannot describe the same slider differently.
    public var unit: AxisUnit? {
        switch self {
        case .lineSpacing, .margins: .multiple
        case .characterSpacing, .wordSpacing, .paragraphSpacing: .em
        case .fontSize, .fontFamily, .boldText, .textAlignment: nil
        }
    }

    /// How far one adjustment moves the value.
    ///
    /// A tenth of the range, rather than a table of five hand-picked numbers that
    /// would drift apart. Ten is what makes the ticks Android draws read as a scale
    /// rather than as noise, and no reader needs a line height of 1.42.
    ///
    /// It also stops a drag from submitting a preference change per frame to the
    /// renderer, each of which relays out the page.
    public var step: Double? {
        guard let range = sliderRange else { return nil }
        return (range.upperBound - range.lowerBound) / Double(ThemeAxis.stepsPerAxis)
    }

    /// Positions on every fine axis.
    public static let stepsPerAxis = 10
}

/// What a slider's number is measured in.
public enum AxisUnit: String, Sendable, CaseIterable {
    /// A multiplier of the renderer's own value — "1.5 times".
    case multiple
    /// A fraction of the current type size — "0.15 em".
    case em
}

public extension ThemeValues {
    /// The value of one axis, for a slider to read.
    ///
    /// A keyed accessor rather than nine bindings in the sheet: the sheet then draws
    /// one slider in a loop, and adding an axis is a case here instead of a new
    /// block of view code.
    func value(of axis: ThemeAxis) -> Double {
        switch axis {
        case .lineSpacing: lineHeight
        case .characterSpacing: letterSpacing
        case .wordSpacing: wordSpacing
        case .paragraphSpacing: paragraphSpacing
        case .margins: pageMargins
        case .fontSize: Double(fontSize.rawValue)
        case .fontFamily, .boldText, .textAlignment: 0
        }
    }

    /// The same values with one axis moved.
    func setting(_ axis: ThemeAxis, to value: Double) -> ThemeValues {
        var copy = self
        switch axis {
        case .lineSpacing: copy.lineHeight = value
        case .characterSpacing: copy.letterSpacing = value
        case .wordSpacing: copy.wordSpacing = value
        case .paragraphSpacing: copy.paragraphSpacing = value
        case .margins: copy.pageMargins = value
        // The ladder and the pickers are set directly; a Double cannot express them.
        case .fontSize, .fontFamily, .boldText, .textAlignment: break
        }
        return copy
    }
}

public extension ThemePreset {
    /// The preset's own typography.
    ///
    /// From `design.md`'s preset table. The colours are not here — they are token
    /// values under `readingThemes`, so they go through the AAA contrast gate
    /// instead of being written down twice.
    var values: ThemeValues {
        switch self {
        // Nothing overridden but size, which is what makes Original Original.
        case .original:
            ThemeValues()

        // "Soft off-white text on deep neutral, tightened spacing."
        case .quiet:
            ThemeValues(
                typeface: .sourceSerif,
                lineHeight: 1.3,
                letterSpacing: 0,
                paragraphSpacing: 0.4,
                pageMargins: 1
            )

        // "Book-stock white, serif, comfortable default spacing." Literata, which
        // `design.md` names as Paper's default and which was designed for screens.
        case .paper:
            ThemeValues(typeface: .literata, lineHeight: 1.5, paragraphSpacing: 0.6)

        // "Heavier weight, wider spacing. For low vision without leaving the
        // aesthetic." One step up as well: the reader who picks Bold is telling us
        // the default was too small.
        case .bold:
            ThemeValues(
                typeface: .sans,
                fontSize: .large,
                isBold: true,
                lineHeight: 1.6,
                letterSpacing: 0.02,
                wordSpacing: 0.05,
                paragraphSpacing: 0.8,
                pageMargins: 1
            )

        // "Cream-on-brown, generous line height. Long evening sessions." EB
        // Garamond, for the different voice `design.md` asks Calm to have.
        case .calm:
            ThemeValues(typeface: .ebGaramond, lineHeight: 1.75, paragraphSpacing: 0.8, pageMargins: 1.2)

        // "Narrow measure, high contrast, minimal decoration. Fewest words per
        // line." The narrow measure is the wide margin.
        case .focus:
            ThemeValues(
                typeface: .bitter,
                lineHeight: 1.5,
                paragraphSpacing: 0.5,
                pageMargins: 1.8,
                textAlignment: .left
            )
        }
    }
}
