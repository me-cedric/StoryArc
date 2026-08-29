import Foundation
import Testing

@testable import StoryArcCore

/// Mirrors Android's `ExcerptTest`, assertion for assertion.
@Suite("Excerpts")
struct ExcerptTests {

    private let prose = """
        Alpha bravo charlie delta echo foxtrot golf hotel india juliett kilo lima \
        mike november oscar papa quebec romeo sierra tango uniform victor whisky.
        """

    @Test("An excerpt starts at a word, not in the middle of one")
    func startsAtAWord() {
        let text = Excerpt.at(prose, fraction: 0.5, length: 40)
        #expect(prose.contains(" \(text)") || prose.hasPrefix(text))
    }

    @Test("An excerpt ends at a word when there was more to come")
    func endsAtAWord() {
        let text = Excerpt.at(prose, fraction: 0, length: 40)
        #expect(!text.hasSuffix(" "))
        #expect(prose.hasPrefix(text))
        #expect(text.count <= 40)
    }

    @Test("The end of the text is not trimmed away looking for a space")
    func keepsTheTail() {
        #expect(Excerpt.at(prose, fraction: 0.99, length: 400).hasSuffix("whisky."))
    }

    @Test("A fraction outside the text is pulled back into it")
    func clampsTheFraction() {
        #expect(Excerpt.at(prose, fraction: 1) == Excerpt.at(prose, fraction: 4.2))
        #expect(Excerpt.at(prose, fraction: 0) == Excerpt.at(prose, fraction: -1))
    }

    @Test("Nothing to quote gives nothing, rather than whitespace")
    func emptyStaysEmpty() {
        #expect(Excerpt.at("", fraction: 0.5).isEmpty)
        #expect(Excerpt.at("   \n  ", fraction: 0.5).isEmpty)
    }

    @Test("Markup is not part of the text")
    func stripsMarkup() {
        #expect(Excerpt.plainText("<p class=\"x\">Alpha <em>bravo</em> charlie.</p>")
            == "Alpha bravo charlie.")
    }

    @Test("A script is not text, whatever a tag stripper thinks")
    func stripsScripts() {
        let markup = "<p>Alpha</p><script>var hidden = 'bravo';</script><p>charlie</p>"
        let text = Excerpt.plainText(markup)
        #expect(!text.contains("hidden"))
        #expect(text == "Alpha charlie")
    }

    @Test("The head is not text a reader ever saw")
    func stripsTheHead() {
        let markup = "<html><head><title>Chapter Two</title></head><body><p>Alpha bravo.</p></body></html>"
        #expect(Excerpt.plainText(markup) == "Alpha bravo.")
    }

    @Test("The entities a book actually uses come back as characters")
    func decodesEntities() {
        #expect(Excerpt.plainText("<p>Salt &amp; pepper</p>") == "Salt & pepper")
        #expect(Excerpt.plainText("<p>a&nbsp;b</p>") == "a b")
    }
}
