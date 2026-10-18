import Foundation
import StoryArcCore

/// The reader's own typography for reflowable text, kept per Mac, and the axes it sends the renderer.
///
/// `ebook-reader`, *Typography controls* and *An axis is inert while publisher styles are on*. The values are
/// the phones' `ThemeValues`; this is the Mac's copy of iOS's `ReadiumMapping`, in the names the web toolkit
/// takes (`pageGutter` in pixels where the native toolkits say `pageMargins`). The toolkit has no publisher-styles
/// flag of its own: a user property overrides the publication's stylesheet once it is set, so keeping the
/// publisher's styles is sending none of the axes that need them off, the rule `ThemeAxis.requiresPublisherStylesOff`
/// states. Font size, family, weight and margins apply under every preset, as on the phones.
enum EpubTypography {
    static let valuesKey = "app.storyarc.mac.epubTypography"
    static let scrollKey = "app.storyarc.mac.epubScroll"

    /// The typefaces this build carries. The phones bundle five more; the Mac does not ship their files yet.
    static let typefaces: [ReaderTypeface] = [.publisher, .serif, .sans]

    /// The base gutter one margin step stands for, in CSS pixels.
    static let gutterUnit: Double = 24

    static var values: ThemeValues {
        get {
            guard let data = UserDefaults.standard.data(forKey: valuesKey),
                  let values = try? JSONDecoder().decode(ThemeValues.self, from: data)
            else { return ThemeValues() }
            return values
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: valuesKey) }
    }

    /// Whether reflowable text scrolls rather than turns pages (`ebook-reader`, *Scroll mode*).
    static var scrolls: Bool {
        get { UserDefaults.standard.bool(forKey: scrollKey) }
        set { UserDefaults.standard.set(newValue, forKey: scrollKey) }
    }

    /// Whether an axis reaches the page under `preset`.
    static func isEffective(_ axis: ThemeAxis, under preset: ThemePreset) -> Bool {
        ReadingTheme(preset: preset).isEffective(axis)
    }

    /// The renderer's axes for `values` under `preset`.
    static func axes(_ values: ThemeValues, preset: ThemePreset, scroll: Bool) -> [String: AnyHashable] {
        var axes: [String: AnyHashable] = [
            "fontSize": values.fontSize.fraction,
            "pageGutter": (values.pageMargins * gutterUnit).rounded(),
            "scroll": scroll,
        ]
        if let family = family(of: values.typeface) { axes["fontFamily"] = family }
        if values.isBold { axes["fontWeight"] = 1.5 }
        guard !preset.keepsPublisherStyles else { return axes }
        axes["lineHeight"] = values.lineHeight
        axes["letterSpacing"] = values.letterSpacing
        axes["wordSpacing"] = values.wordSpacing
        axes["paragraphSpacing"] = values.paragraphSpacing
        if values.isHyphenated { axes["hyphens"] = true }
        switch values.textAlignment {
        case .publisher: break
        case .left: axes["textAlign"] = "left"
        case .justified: axes["textAlign"] = "justify"
        }
        return axes
    }

    /// The CSS family for a typeface, or nil for the publication's own.
    static func family(of typeface: ReaderTypeface) -> String? {
        switch typeface {
        case .publisher: nil
        case .serif: "serif"
        case .sans: "sans-serif"
        case .literata, .sourceSerif, .ebGaramond, .bitter, .atkinsonHyperlegible: nil
        }
    }
}

extension EpubReaderModel {
    /// A preset's colours with the reader's typography over them: what a theme message carries.
    static func readerAxes(_ preset: ThemePreset) -> [String: AnyHashable] {
        var all = axes(of: preset).merging(
            EpubTypography.axes(EpubTypography.values, preset: preset, scroll: EpubTypography.scrolls)
        ) { _, typography in typography }
        let darken = EpubLook.darken(EpubLook.brightness)
        if darken > 0 { all["darkenFilter"] = darken }
        return all
    }

    /// Saves the reader's typography and puts it on the page. A theme message replaces every axis, so the
    /// preset is sent again with the new values rather than the values alone.
    func apply(_ values: ThemeValues, scroll: Bool) {
        EpubTypography.values = values
        EpubTypography.scrolls = scroll
        apply(theme)
    }

    /// The publication's contents, from the manifest, as locators the renderer goes to.
    static func locator(for link: EpubWebLink) -> String {
        let object: [String: Any] = ["href": link.href, "type": link.type, "locations": [String: Any]()]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
