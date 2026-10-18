import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// The reader's typography as the renderer receives it (`ebook-reader`, *Typography controls*, *An axis is inert
/// while publisher styles are on*, *Scroll mode*), the Mac's copy of iOS's `ReadiumMapping` cases.
@MainActor
@Suite("EPUB typography")
struct EpubTypographyTests {
    private let values = ThemeValues(
        typeface: .serif, fontSize: .larger, isBold: true, lineHeight: 1.8,
        pageMargins: 1.5, textAlignment: .justified, isHyphenated: true
    )

    @Test("Size, family, weight and margins reach the page under every preset")
    func alwaysEffective() {
        for preset in ThemePreset.allCases {
            let axes = EpubTypography.axes(values, preset: preset, scroll: false)
            #expect(axes["fontSize"] == AnyHashable(1.3))
            #expect(axes["fontFamily"] == AnyHashable("serif"))
            #expect(axes["fontWeight"] == AnyHashable(1.5))
            #expect(axes["pageGutter"] == AnyHashable(36.0))
        }
    }

    @Test("Original keeps the publisher's spacing, alignment and hyphenation; another preset sends them")
    func publisherStylesHoldUnderOriginal() {
        let original = EpubTypography.axes(values, preset: .original, scroll: false)
        #expect(original["lineHeight"] == nil)
        #expect(original["textAlign"] == nil)
        #expect(original["hyphens"] == nil)
        let quiet = EpubTypography.axes(values, preset: .quiet, scroll: false)
        #expect(quiet["lineHeight"] == AnyHashable(1.8))
        #expect(quiet["textAlign"] == AnyHashable("justify"))
        #expect(quiet["hyphens"] == AnyHashable(true))
    }

    @Test("The publisher's typeface sends no family, and scroll mode is one flag")
    func publisherTypefaceAndScroll() {
        let axes = EpubTypography.axes(ThemeValues(), preset: .paper, scroll: true)
        #expect(axes["fontFamily"] == nil)
        #expect(axes["fontWeight"] == nil)
        #expect(axes["scroll"] == AnyHashable(true))
        #expect(axes["textAlign"] == nil)
    }

    @Test("A theme message carries the preset's colours with the typography over them")
    func themeCarriesBoth() {
        let saved = EpubTypography.values
        defer { EpubTypography.values = saved }
        EpubTypography.values = values
        let axes = EpubReaderModel.readerAxes(.quiet)
        #expect(axes["backgroundColor"] != nil)
        #expect(axes["fontSize"] == AnyHashable(1.3))
    }

    @Test("A contents entry becomes a locator the renderer goes to")
    func contentsLocator() throws {
        let link = EpubWebLink(href: "OEBPS/ch2.xhtml", type: "application/xhtml+xml", title: "Two", rel: nil)
        let json = EpubReaderModel.locator(for: link)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["href"] as? String == "OEBPS/ch2.xhtml")
    }
}
