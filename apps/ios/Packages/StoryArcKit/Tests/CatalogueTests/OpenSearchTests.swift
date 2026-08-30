import Foundation
import Testing

@testable import Catalogue

/// The document an OPDS 1.2 catalogue advertises its search through.
///
/// `opds-catalog`: "when a catalogue advertises an OpenSearch description, searching within
/// that source queries the server rather than filtering locally". A 2.0 feed carries the
/// template in the link's own href; a 1.2 feed points at one of these, which is the commoner
/// of the two shapes and the one nothing followed until now — every such catalogue fell back
/// to filtering what was already loaded.
///
/// Fixtures hand-written rather than captured, for the reason `OpdsParsingTests` gives: each
/// is a claim about the standard rather than about one server's build.
///
/// Android's `OpenSearchTest` asserts these cases in this order.
struct OpenSearchTests {
    private let document = URL(string: "https://library.example/opds/opensearch.xml")!

    private func template(_ xml: String) -> String? {
        OpenSearchDescription.template(Data(xml.utf8), baseURL: document)
    }

    @Test func anAbsoluteTemplateIsTakenAsWritten() {
        let found = template("""
        <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
          <ShortName>Library</ShortName>
          <Url type="application/atom+xml;profile=opds-catalog"
               template="https://library.example/search?q={searchTerms}"/>
        </OpenSearchDescription>
        """)
        #expect(found == "https://library.example/search?q={searchTerms}")
    }

    @Test func aRelativeTemplateIsResolvedAgainstTheDocument() {
        let found = template("""
        <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
          <Url type="application/atom+xml" template="../search?q={searchTerms}"/>
        </OpenSearchDescription>
        """)
        #expect(found == "https://library.example/search?q={searchTerms}")
    }

    @Test func thePlaceholderSurvivesResolution() {
        // Percent-encoding the braces would leave a template nothing can substitute into,
        // and `fill` would then refuse it as a search that matched everything.
        let found = template("""
        <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
          <Url type="application/atom+xml" template="search?q={searchTerms}&amp;page={startPage?}"/>
        </OpenSearchDescription>
        """)
        #expect(found?.contains("{searchTerms}") == true)
    }

    @Test func theOpdsProfileWinsOverAPage() {
        // Calibre-Web's own document lists the HTML search first.
        let found = template("""
        <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
          <Url type="text/html" template="https://library.example/ui?q={searchTerms}"/>
          <Url type="application/atom+xml;profile=opds-catalog"
               template="https://library.example/opds/search?q={searchTerms}"/>
        </OpenSearchDescription>
        """)
        #expect(found == "https://library.example/opds/search?q={searchTerms}")
    }

    @Test func atomWinsWhenNoProfileIsDeclared() {
        let found = template("""
        <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
          <Url type="text/html" template="https://library.example/ui?q={searchTerms}"/>
          <Url type="application/atom+xml" template="https://library.example/feed?q={searchTerms}"/>
        </OpenSearchDescription>
        """)
        #expect(found == "https://library.example/feed?q={searchTerms}")
    }

    @Test func aDocumentOfferingOnlyAPageOffersNothing() {
        let found = template("""
        <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
          <Url type="text/html" template="https://library.example/ui?q={searchTerms}"/>
        </OpenSearchDescription>
        """)
        #expect(found == nil)
    }

    @Test func aUrlWithoutATemplateIsSkipped() {
        let found = template("""
        <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
          <Url type="application/atom+xml"/>
          <Url type="application/atom+xml" template="https://library.example/s?q={searchTerms}"/>
        </OpenSearchDescription>
        """)
        #expect(found == "https://library.example/s?q={searchTerms}")
    }

    @Test func somethingThatIsNotADescriptionDocumentOffersNothing() {
        #expect(template("<html><body>Sign in</body></html>") == nil)
    }
}
