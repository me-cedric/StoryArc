import Foundation
import Testing

@testable import Catalogue

/// The two dialects, read from the shapes real servers send.
///
/// Fixtures are hand-written rather than captured, so each one is a claim about the
/// standard rather than about one server's build. Where a server is named, that server is
/// the reason the shape is unusual.
struct OpdsParsingTests {
    private let base = URL(string: "https://library.example/opds/")!

    // MARK: OPDS 1.2

    private let atomNavigation = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
      <title>Example Library</title>
      <link rel="self" href="/opds/" type="application/atom+xml;profile=opds-catalog"/>
      <link rel="start" href="/opds/" type="application/atom+xml;profile=opds-catalog"/>
      <link rel="search" href="/opds/search?q={searchTerms}"
            type="application/atom+xml"/>
      <link rel="subsection" href="unread" title="Unread" opds:count="12"
            type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
      <link rel="subsection" href="series" title="Series"
            type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
    </feed>
    """

    @Test func atomNavigationFeedYieldsSections() throws {
        let feed = try OpdsDocument.parse(Data(atomNavigation.utf8), baseURL: base)
        #expect(feed.title == "Example Library")
        #expect(feed.publications.isEmpty)
        #expect(feed.navigation.map(\.title) == ["Unread", "Series"])
        #expect(feed.navigation.first?.href.absoluteString == "https://library.example/opds/unread")
        #expect(feed.searchTemplate == "https://library.example/opds/search?q={searchTerms}")
    }

    @Test func selfStartAndUpAreNotSections() throws {
        let feed = try OpdsDocument.parse(Data(atomNavigation.utf8), baseURL: base)
        #expect(!feed.navigation.contains { $0.title.isEmpty })
        #expect(feed.navigation.count == 2)
    }

    @Test func countIsReadWhenGivenAndAbsentOtherwise() throws {
        let feed = try OpdsDocument.parse(Data(atomNavigation.utf8), baseURL: base)
        #expect(feed.navigation[0].count == 12)
        #expect(feed.navigation[1].count == nil)
    }

    private let atomAcquisition = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Unread</title>
      <link rel="next" href="unread?page=2" type="application/atom+xml"/>
      <link rel="http://opds-spec.org/facet" href="?lang=en" title="English"
            opds:facetGroup="Language" opds:activeFacet="true" thr:count="40"
            xmlns:opds="http://opds-spec.org/2010/catalog"
            xmlns:thr="http://purl.org/syndication/thread/1.0"/>
      <entry>
        <title>The Long Field</title>
        <id>urn:uuid:1</id>
        <updated>2026-08-01T10:00:00Z</updated>
        <author><name>Ada Lovelace</name></author>
        <summary>A field, at length.</summary>
        <link rel="http://opds-spec.org/image" href="cover/1.jpg" type="image/jpeg"/>
        <link rel="http://opds-spec.org/image/thumbnail" href="thumb/1.jpg" type="image/jpeg"/>
        <link rel="http://opds-spec.org/acquisition" href="download/1.epub"
              type="application/epub+zip"/>
        <link rel="http://opds-spec.org/acquisition" href="download/1.pdf"
              type="application/pdf"/>
      </entry>
      <entry>
        <title>Borrowed Only</title>
        <id>urn:uuid:2</id>
        <link rel="http://opds-spec.org/acquisition/borrow" href="borrow/2"
              type="application/epub+zip"/>
      </entry>
      <entry>
        <id>urn:uuid:3</id>
      </entry>
    </feed>
    """

    @Test func atomAcquisitionFeedYieldsEntries() throws {
        let feed = try OpdsDocument.parse(Data(atomAcquisition.utf8), baseURL: base)
        #expect(feed.isAcquisition)
        // The third entry has no title, so there is nothing to show and it is dropped.
        #expect(feed.publications.map(\.title) == ["The Long Field", "Borrowed Only"])
        #expect(feed.next?.absoluteString == "https://library.example/opds/unread?page=2")

        let first = try #require(feed.publications.first)
        #expect(first.authors == ["Ada Lovelace"])
        #expect(first.summary == "A field, at length.")
        #expect(first.cover?.lastPathComponent == "1.jpg")
        #expect(first.thumbnail?.path.contains("thumb") == true)
        #expect(first.updated != nil)
        #expect(first.acquisitions.map(\.mediaType) == ["application/epub+zip", "application/pdf"])
        #expect(first.acquisitions.allSatisfy { $0.kind == .direct })
    }

    @Test func facetsCarryTheirGroupAndActiveState() throws {
        let feed = try OpdsDocument.parse(Data(atomAcquisition.utf8), baseURL: base)
        let facet = try #require(feed.facets.first)
        #expect(facet.group == "Language")
        #expect(facet.title == "English")
        #expect(facet.isActive)
    }

    @Test func aBorrowLinkIsNamedRatherThanDropped() throws {
        let feed = try OpdsDocument.parse(Data(atomAcquisition.utf8), baseURL: base)
        let borrowed = try #require(feed.publications.last)
        #expect(borrowed.acquisitions.map(\.kind) == [.borrow])
        // `opds-catalog`: an unsupported acquisition type is stated, not failed silently.
        #expect(borrowed.acquisitions.allSatisfy { !$0.kind.isFetchable })
    }

    @Test func openAccessIsDistinguishedFromPlainAcquisition() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title><entry><title>e</title>
        <link rel="http://opds-spec.org/acquisition/open-access" href="free.epub"
              type="application/epub+zip"/></entry></feed>
        """
        let feed = try OpdsDocument.parse(Data(xml.utf8), baseURL: base)
        #expect(feed.publications.first?.acquisitions.first?.kind == .open)
    }

    @Test func anUnknownAcquisitionRelationIsIndirectRatherThanLost() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title><entry><title>e</title>
        <link rel="http://opds-spec.org/acquisition/lend-later" href="x"
              type="application/epub+zip"/></entry></feed>
        """
        let feed = try OpdsDocument.parse(Data(xml.utf8), baseURL: base)
        #expect(feed.publications.first?.acquisitions.first?.kind == .indirect)
    }

    @Test func aSearchLinkWithoutATemplateIsADescriptionDocument() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title>
        <link rel="search" href="opensearch.xml"
              type="application/opensearchdescription+xml"/></feed>
        """
        let feed = try OpdsDocument.parse(Data(xml.utf8), baseURL: base)
        #expect(feed.searchTemplate == nil)
        #expect(feed.searchDescription?.lastPathComponent == "opensearch.xml")
    }

    // MARK: OPDS 2.0

    private let json = """
    {
      "metadata": { "title": "Example Library" },
      "links": [
        { "rel": "self", "href": "/opds", "type": "application/opds+json" },
        { "rel": ["next"], "href": "/opds?page=2", "type": "application/opds+json" },
        { "rel": "search", "href": "/opds/search{?query}", "templated": true }
      ],
      "navigation": [
        { "title": "Unread", "href": "/opds/unread", "type": "application/opds+json",
          "properties": { "numberOfItems": 12 } }
      ],
      "groups": [
        {
          "navigation": [
            { "title": "Series", "href": "/opds/series", "type": "application/opds+json" }
          ],
          "publications": [
            {
              "metadata": {
                "identifier": "urn:uuid:9", "title": "Grouped Title",
                "author": "Grace Hopper"
              },
              "links": [
                { "href": "/download/9.epub", "type": "application/epub+zip",
                  "rel": "http://opds-spec.org/acquisition" }
              ]
            }
          ]
        }
      ],
      "facets": [
        {
          "metadata": { "title": "Language" },
          "links": [
            { "title": "English", "href": "/opds?lang=en",
              "properties": { "numberOfItems": 40 } }
          ]
        }
      ],
      "publications": [
        {
          "metadata": {
            "title": "Harbour Lights 02",
            "author": [{ "name": "Ada Lovelace" }, "Alan Turing"],
            "belongsTo": { "series": { "name": "Harbour Lights", "position": 2 } },
            "modified": "2026-08-01T10:00:00Z",
            "description": "Second."
          },
          "images": [
            { "href": "/cover/2.jpg", "width": 1200 },
            { "href": "/thumb/2.jpg", "width": 200 }
          ],
          "links": [
            { "href": "/download/2.epub", "type": "application/epub+zip" }
          ]
        }
      ]
    }
    """

    @Test func jsonFeedIsDetectedAndRead() throws {
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        #expect(feed.title == "Example Library")
        #expect(feed.next?.absoluteString == "https://library.example/opds?page=2")
        #expect(feed.searchTemplate == "https://library.example/opds/search{?query}")
        #expect(feed.searchDescription == nil)
    }

    @Test func groupsAreFlattenedIntoTheFeed() throws {
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        #expect(feed.navigation.map(\.title) == ["Unread", "Series"])
        #expect(feed.publications.map(\.title) == ["Harbour Lights 02", "Grouped Title"])
    }

    @Test func anAuthorIsReadWhicheverShapeItTakes() throws {
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        #expect(feed.publications.first?.authors == ["Ada Lovelace", "Alan Turing"])
        #expect(feed.publications.last?.authors == ["Grace Hopper"])
    }

    @Test func theLargestImageIsTheCoverAndTheSmallestTheThumbnail() throws {
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        let entry = try #require(feed.publications.first)
        #expect(entry.cover?.lastPathComponent == "2.jpg")
        #expect(entry.cover?.path.contains("cover") == true)
        #expect(entry.thumbnail?.path.contains("thumb") == true)
    }

    @Test func seriesAndPositionAreRead() throws {
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        #expect(feed.publications.first?.series == "Harbour Lights")
        #expect(feed.publications.first?.seriesIndex == 2)
    }

    @Test func aLinkWithNoRelationIsStillAnAcquisition() throws {
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        #expect(feed.publications.first?.acquisitions.map(\.kind) == [.direct])
    }

    // MARK: What arrived instead

    @Test func anHtmlPageIsNamedAsOne() {
        let page = "<!DOCTYPE html><html><head><title>Log in</title></head></html>"
        #expect(throws: OpdsError.notAFeed(received: .html)) {
            try OpdsDocument.parse(Data(page.utf8), baseURL: base)
        }
    }

    @Test func anXhtmlPageIsAlsoAPageNotAFeed() {
        let page = """
        <?xml version="1.0"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body>Nope</body></html>
        """
        #expect(throws: OpdsError.notAFeed(received: .html)) {
            try OpdsDocument.parse(Data(page.utf8), baseURL: base)
        }
    }

    @Test func anEmptyBodyIsNamedAsEmpty() {
        #expect(throws: OpdsError.empty) {
            try OpdsDocument.parse(Data("   \n".utf8), baseURL: base)
        }
    }

    @Test func someOtherJsonApiIsNotAFeed() {
        #expect(throws: OpdsError.notAFeed(received: .unrecognised(contentType: "application/json"))) {
            try OpdsDocument.parse(Data(#"{"ok":true}"#.utf8), baseURL: base)
        }
    }

    @Test func aBodyThatIsNeitherDialectSaysWhatItWas() {
        #expect(throws: OpdsError.notAFeed(received: .unrecognised(contentType: "text/csv"))) {
            try OpdsDocument.parse(Data("a,b\n1,2".utf8), contentType: "text/csv", baseURL: base)
        }
    }

    @Test func aWrongContentTypeDoesNotStopACorrectBody() throws {
        // Several servers send `application/octet-stream` for a perfectly good Atom feed.
        let feed = try OpdsDocument.parse(
            Data(atomNavigation.utf8),
            contentType: "application/octet-stream",
            baseURL: base
        )
        #expect(feed.title == "Example Library")
    }

    // MARK: Authentication challenges

    @Test func aChallengeNamesItsScheme() {
        #expect(OpdsError.AuthenticationScheme(challenge: "Basic realm=\"opds\"") == .basic)
        #expect(OpdsError.AuthenticationScheme(challenge: "Bearer") == .bearer)
        #expect(OpdsError.AuthenticationScheme(challenge: "Digest qop=auth") == nil)
    }
}

/// What a typed address becomes.
///
/// The one piece of the add-a-catalogue flow that is not a network call, and the one that
/// decides whether a password travels in the clear.
struct OpdsAddressTests {
    @Test func aBareHostBecomesHttps() throws {
        let url = try #require(OpdsDocument.address(from: "library.example.com/opds"))
        #expect(url.absoluteString == "https://library.example.com/opds")
    }

    @Test func anExplicitSchemeIsKept() throws {
        // A reader who typed `http` meant it — usually a server on their own network. The
        // default is the secure one; the override is theirs.
        let url = try #require(OpdsDocument.address(from: "http://nas.local:8080/opds"))
        #expect(url.absoluteString == "http://nas.local:8080/opds")
    }

    @Test func surroundingSpaceIsIgnored() throws {
        let url = try #require(OpdsDocument.address(from: "  komga.local/opds  "))
        #expect(url.absoluteString == "https://komga.local/opds")
    }

    @Test func somethingWithNoHostIsNotAnAddress() {
        #expect(OpdsDocument.address(from: "") == nil)
        #expect(OpdsDocument.address(from: "   ") == nil)
        #expect(OpdsDocument.address(from: "https://") == nil)
        #expect(OpdsDocument.address(from: "not a host at all") == nil)
    }
}
