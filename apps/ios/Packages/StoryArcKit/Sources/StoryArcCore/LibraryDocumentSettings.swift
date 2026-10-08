public import Foundation

/// ``AppSettings`` as the document spells it.
///
/// A shape of its own rather than ``AppSettings`` itself, for two reasons. An enum case is a
/// `String` here so that the conversion is visible and testable — nesting the domain type
/// would make the document's wire a side effect of a Swift raw value, and a rename would
/// change every file this app has ever written with nothing to catch it. And the document
/// carries the union of what the two platforms hold, which is not what either one holds.
///
/// A field for a setting this platform does not have is read and dropped rather than
/// invented. `library-portability` / *A field this version does not know* allows exactly
/// that: "the field is ignored and the rest is imported, and a re-export does not have to
/// carry it back".
public struct DocumentSettings: Sendable, Equatable, Codable {
    public var appearance: String
    public var language: String?
    public var turnPagesByTappingTheEdges: Bool
    public var linkReadingThemeToAppearance: Bool
    public var lightReadingTheme: String
    public var darkReadingTheme: String
    public var downloadOverWifiOnly: Bool
    public var maximumDownloadBytes: Int64?
    public var removeDownloadsAfterFinishing: Bool

    /// When each field last changed, and on which device. See ``SettingsStamps``.
    public var changed: [String: DocumentStamp]?

    public init(
        appearance: String = AppearanceMode.system.rawValue,
        language: String? = nil,
        turnPagesByTappingTheEdges: Bool = true,
        linkReadingThemeToAppearance: Bool = false,
        lightReadingTheme: String = ThemePreset.paper.rawValue,
        darkReadingTheme: String = ThemePreset.quiet.rawValue,
        downloadOverWifiOnly: Bool = false,
        maximumDownloadBytes: Int64? = nil,
        removeDownloadsAfterFinishing: Bool = false,
        changed: [String: DocumentStamp]? = nil
    ) {
        self.changed = changed
        self.appearance = appearance
        self.language = language
        self.turnPagesByTappingTheEdges = turnPagesByTappingTheEdges
        self.linkReadingThemeToAppearance = linkReadingThemeToAppearance
        self.lightReadingTheme = lightReadingTheme
        self.darkReadingTheme = darkReadingTheme
        self.downloadOverWifiOnly = downloadOverWifiOnly
        self.maximumDownloadBytes = maximumDownloadBytes
        self.removeDownloadsAfterFinishing = removeDownloadsAfterFinishing
    }

    public init(_ settings: AppSettings) {
        self.init(
            appearance: settings.appearance.rawValue,
            language: settings.language,
            turnPagesByTappingTheEdges: settings.turnPagesByTappingTheEdges,
            linkReadingThemeToAppearance: settings.linkReadingThemeToAppearance,
            lightReadingTheme: settings.lightReadingTheme.rawValue,
            darkReadingTheme: settings.darkReadingTheme.rawValue,
            downloadOverWifiOnly: settings.downloadOverWifiOnly,
            maximumDownloadBytes: settings.maximumDownloadBytes,
            removeDownloadsAfterFinishing: settings.removeDownloadsAfterFinishing
        )
    }

    /// The settings this names, with a value this build does not know left at its default.
    ///
    /// A setting is a preference, and losing one is worth far less than refusing the whole
    /// import — the same trade every store in this app already makes on unreadable data.
    public var settings: AppSettings { settings(keeping: .defaults) }

    /// The settings this names, over the device's own: a setting the document does not carry
    /// at all, such as the cover lookup, keeps the device's answer.
    public func settings(keeping device: AppSettings) -> AppSettings {
        var settings = device
        settings.appearance = AppearanceMode(rawValue: appearance) ?? .system
        settings.language = language
        settings.turnPagesByTappingTheEdges = turnPagesByTappingTheEdges
        settings.linkReadingThemeToAppearance = linkReadingThemeToAppearance
        settings.lightReadingTheme = ThemePreset(rawValue: lightReadingTheme) ?? .paper
        settings.darkReadingTheme = ThemePreset(rawValue: darkReadingTheme) ?? .quiet
        settings.downloadOverWifiOnly = downloadOverWifiOnly
        settings.maximumDownloadBytes = maximumDownloadBytes
        settings.removeDownloadsAfterFinishing = removeDownloadsAfterFinishing
        return settings
    }

    /// Decodes what is there and defaults what is not. See ``LibraryBody/init(from:)``.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DocumentSettings()
        self.init(
            appearance: try values.decodeIfPresent(String.self, forKey: .appearance)
                ?? fallback.appearance,
            language: try values.decodeIfPresent(String.self, forKey: .language),
            turnPagesByTappingTheEdges: try values.decodeIfPresent(
                Bool.self, forKey: .turnPagesByTappingTheEdges
            ) ?? fallback.turnPagesByTappingTheEdges,
            linkReadingThemeToAppearance: try values.decodeIfPresent(
                Bool.self, forKey: .linkReadingThemeToAppearance
            ) ?? fallback.linkReadingThemeToAppearance,
            lightReadingTheme: try values.decodeIfPresent(String.self, forKey: .lightReadingTheme)
                ?? fallback.lightReadingTheme,
            darkReadingTheme: try values.decodeIfPresent(String.self, forKey: .darkReadingTheme)
                ?? fallback.darkReadingTheme,
            downloadOverWifiOnly: try values.decodeIfPresent(
                Bool.self, forKey: .downloadOverWifiOnly
            ) ?? fallback.downloadOverWifiOnly,
            maximumDownloadBytes: try values.decodeIfPresent(
                Int64.self, forKey: .maximumDownloadBytes
            ),
            removeDownloadsAfterFinishing: try values.decodeIfPresent(
                Bool.self, forKey: .removeDownloadsAfterFinishing
            ) ?? fallback.removeDownloadsAfterFinishing,
            changed: try values.decodeIfPresent([String: DocumentStamp].self, forKey: .changed)
        )
    }
}

/// ``ReadingTheme`` as the document spells it: the preset, the axes moved off it, and the
/// reader's own colours when they chose some.
public struct DocumentReadingTheme: Sendable, Equatable, Codable {
    public var preset: String

    /// Sorted, because this is a `Set` on both platforms and a set has no order — so two
    /// exports of one library would otherwise differ in a way a diff reports and a reader
    /// cannot explain.
    public var deviations: [String]

    public var custom: ReaderPalette?

    public init(preset: String, deviations: [String] = [], custom: ReaderPalette? = nil) {
        self.preset = preset
        self.deviations = deviations
        self.custom = custom
    }

    public init(_ theme: ReadingTheme) {
        self.init(
            preset: theme.preset.rawValue,
            deviations: theme.deviations.map(\.rawValue).sorted(),
            custom: theme.custom
        )
    }

    public var theme: ReadingTheme {
        ReadingTheme(
            preset: ThemePreset(rawValue: preset) ?? .paper,
            deviations: Set(deviations.compactMap(ThemeAxis.init(rawValue:))),
            custom: custom
        )
    }
}

/// ``ThemeValues`` as the document spells it.
///
/// ``fontSizePercent`` is a number and says its unit. iOS backs ``FontSizeStep`` with the
/// percentage itself and Android backs it with a name, so neither platform's own spelling is
/// one the other can read; the percentage is the value both of them actually mean.
public struct DocumentThemeValues: Sendable, Equatable, Codable {
    public var typeface: String
    public var fontSizePercent: Int
    public var isBold: Bool
    public var isHyphenated: Bool
    public var lineHeight: Double
    public var letterSpacing: Double
    public var wordSpacing: Double
    public var paragraphSpacing: Double
    public var pageMargins: Double
    public var textAlignment: String

    public init(
        typeface: String = ReaderTypeface.publisher.rawValue,
        fontSizePercent: Int = FontSizeStep.normal.rawValue,
        isBold: Bool = false,
        isHyphenated: Bool = false,
        lineHeight: Double = 1.4,
        letterSpacing: Double = 0,
        wordSpacing: Double = 0,
        paragraphSpacing: Double = 0.5,
        pageMargins: Double = 1,
        textAlignment: String = ReaderTextAlignment.publisher.rawValue
    ) {
        self.typeface = typeface
        self.fontSizePercent = fontSizePercent
        self.isBold = isBold
        self.isHyphenated = isHyphenated
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.wordSpacing = wordSpacing
        self.paragraphSpacing = paragraphSpacing
        self.pageMargins = pageMargins
        self.textAlignment = textAlignment
    }

    public init(_ values: ThemeValues) {
        self.init(
            typeface: values.typeface.rawValue,
            fontSizePercent: values.fontSize.rawValue,
            isBold: values.isBold,
            isHyphenated: values.isHyphenated,
            lineHeight: values.lineHeight,
            letterSpacing: values.letterSpacing,
            wordSpacing: values.wordSpacing,
            paragraphSpacing: values.paragraphSpacing,
            pageMargins: values.pageMargins,
            textAlignment: values.textAlignment.rawValue
        )
    }

    public var values: ThemeValues {
        ThemeValues(
            typeface: ReaderTypeface(rawValue: typeface) ?? .publisher,
            fontSize: FontSizeStep(rawValue: fontSizePercent) ?? .normal,
            isBold: isBold,
            lineHeight: lineHeight,
            letterSpacing: letterSpacing,
            wordSpacing: wordSpacing,
            paragraphSpacing: paragraphSpacing,
            pageMargins: pageMargins,
            textAlignment: ReaderTextAlignment(rawValue: textAlignment) ?? .publisher,
            isHyphenated: isHyphenated
        )
    }
}

/// ``ShelfSettings`` as the document spells it: everything one shelf is read with.
public struct DocumentShelfSettings: Sendable, Equatable, Codable {
    public var theme: DocumentReadingTheme
    public var values: DocumentThemeValues
    public var transition: String
    public var scrollAxis: String?
    public var readingDirection: String?
    public var adjustments: ImageAdjustments
    public var offsetsSpreads: Bool
    public var showsPageSeparator: Bool
    public var fit: String

    public init(
        theme: DocumentReadingTheme = DocumentReadingTheme(preset: ThemePreset.paper.rawValue),
        values: DocumentThemeValues = DocumentThemeValues(),
        transition: String = PageTransition.slide.rawValue,
        scrollAxis: String? = nil,
        readingDirection: String? = nil,
        adjustments: ImageAdjustments = ImageAdjustments(),
        offsetsSpreads: Bool = false,
        showsPageSeparator: Bool = false,
        fit: String = PageFit.screen.rawValue
    ) {
        self.theme = theme
        self.values = values
        self.transition = transition
        self.scrollAxis = scrollAxis
        self.readingDirection = readingDirection
        self.adjustments = adjustments
        self.offsetsSpreads = offsetsSpreads
        self.showsPageSeparator = showsPageSeparator
        self.fit = fit
    }

    public init(_ settings: ShelfSettings) {
        self.init(
            theme: DocumentReadingTheme(settings.theme),
            values: DocumentThemeValues(settings.values),
            transition: settings.transition.rawValue,
            scrollAxis: settings.scrollAxis?.rawValue,
            readingDirection: settings.readingDirection?.rawValue,
            adjustments: settings.adjustments,
            offsetsSpreads: settings.offsetsSpreads,
            showsPageSeparator: settings.showsPageSeparator,
            fit: settings.fit.rawValue
        )
    }

    public var settings: ShelfSettings {
        ShelfSettings(
            theme: theme.theme,
            values: values.values,
            transition: PageTransition(rawValue: transition) ?? .slide,
            scrollAxis: scrollAxis.flatMap(ScrollAxis.init(rawValue:)),
            readingDirection: readingDirection.flatMap(ReadingDirection.init(rawValue:)),
            adjustments: adjustments,
            offsetsSpreads: offsetsSpreads,
            showsPageSeparator: showsPageSeparator,
            fit: PageFit(rawValue: fit) ?? .screen
        )
    }
}
