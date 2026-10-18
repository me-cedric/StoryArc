import Foundation
import StoryArcCore
import SwiftUI
import Testing

@testable import StoryArc

/// Brightness, the light and dark pair, and progress in words (`ebook-reader`, *Theme choice*, *Theme follows
/// appearance*, *Progress display*).
@MainActor
@Suite("EPUB look")
struct EpubLookTests {
    @Test("Brightness dims the page by what it lacks, and full brightness sends no filter")
    func brightness() {
        let saved = EpubLook.brightness
        defer { EpubLook.brightness = saved }
        #expect(EpubLook.darken(1) == 0)
        #expect(EpubLook.darken(0.7) == 30)
        EpubLook.brightness = 1
        #expect(EpubReaderModel.readerAxes(.quiet)["darkenFilter"] == nil)
        EpubLook.brightness = 0.8
        #expect(EpubReaderModel.readerAxes(.quiet)["darkenFilter"] == AnyHashable(20))
    }

    @Test("Following the appearance picks the pair's preset; with the setting off nothing moves")
    func followsAppearance() {
        let saved = (EpubLook.follows, EpubLook.pair)
        defer { EpubLook.follows = saved.0; EpubLook.pair = saved.1 }
        EpubLook.pair = (light: .quiet, dark: .calm)
        EpubLook.follows = false
        #expect(EpubLook.preset(for: .dark) == nil)
        EpubLook.follows = true
        #expect(EpubLook.preset(for: .dark) == .calm)
        #expect(EpubLook.preset(for: .light) == .quiet)
    }

    @Test("A token's hex is a colour, and a preset's swatch uses its own colours")
    func swatchColours() {
        #expect(EpubLook.color(hex: "#ff8000") != nil)
        #expect(EpubLook.color(hex: "nope") == nil)
    }

    @Test("Progress is a share of the book and what is left of the chapter, never a page number")
    func progressInWords() {
        let line = EpubProgressLine.text(total: 0.42, chapter: 0.25)
        #expect(line.contains("42"))
        #expect(line.contains("75"))
    }
}
