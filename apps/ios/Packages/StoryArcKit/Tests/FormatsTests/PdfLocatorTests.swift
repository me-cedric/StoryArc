import Foundation
import Testing

@testable import Formats

/// Mirrors Android's `PdfLocatorTest`, assertion for assertion.
@Suite("PDF locators")
struct PdfLocatorTests {

    @Test("The written form is one exact string, so both platforms write the same record")
    func writesOneString() {
        let locator = PdfLocator(page: 11, start: 340, end: 392)
        #expect(locator.json == #"{"page":11,"start":340,"end":392}"#)
    }

    @Test("A locator round-trips through its own JSON")
    func roundTrips() {
        let locator = PdfLocator(page: 0, start: 0, end: 7)
        #expect(PdfLocator(json: locator.json) == locator)
    }

    @Test("A string that is not a locator reads as nothing rather than as zeros")
    func rejectsNonsense() {
        #expect(PdfLocator(json: "") == nil)
        #expect(PdfLocator(json: "not json at all") == nil)
        // A reflowable locator, which is what the same field holds for an EPUB.
        #expect(PdfLocator(json: #"{"href":"chapter1.xhtml","type":"text/html"}"#) == nil)
    }

    @Test("A run that ends before it starts is refused")
    func rejectsInvertedRun() {
        #expect(PdfLocator(json: #"{"page":1,"start":40,"end":10}"#) == nil)
    }

    @Test("A page before the first one is refused")
    func rejectsNegativePage() {
        #expect(PdfLocator(json: #"{"page":-1,"start":0,"end":10}"#) == nil)
    }

    @Test("An empty run is read, because a caret is a position a reader can be at")
    func readsAnEmptyRun() {
        #expect(PdfLocator(json: #"{"page":2,"start":5,"end":5}"#)
            == PdfLocator(page: 2, start: 5, end: 5))
    }
}
