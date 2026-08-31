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

    // MARK: What an acquisition costs

    /// One entry whose acquisition links carry the sizes given, in the order given.
    ///
    /// `nil` writes the attribute out entirely, which is what most catalogues do, and the
    /// difference between "no size" and "a size of nothing" is the point of several of
    /// these cases.
    private func atomSized(_ lengths: [String?]) -> String {
        let links = lengths.map { length in
            let attribute = length.map { " length=\"\($0)\"" } ?? ""
            return """
            <link rel="http://opds-spec.org/acquisition" href="download.epub"
                  type="application/epub+zip"\(attribute)/>
            """
        }
        return """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title><entry><title>e</title>
        \(links.joined(separator: "\n"))</entry></feed>
        """
    }

    private func atomLengths(_ lengths: [String?]) throws -> [Int64?] {
        let feed = try OpdsDocument.parse(Data(atomSized(lengths).utf8), baseURL: base)
        return feed.publications.first?.acquisitions.map(\.length) ?? []
    }

    @Test func anAtomLinkStatesItsLengthInBytes() throws {
        #expect(try atomLengths(["4096"]) == [4096])
    }

    @Test func anAtomLinkWithNoLengthStatesNoSize() throws {
        #expect(try atomLengths([nil]) == [nil])
    }

    /// A size larger than `Int32` is the ordinary case, not the exotic one: ADR-0008's
    /// worked example is a 400 MB archive, and a 4 GB one is a scanned omnibus.
    @Test func aLengthBeyondFourGigabytesSurvives() throws {
        #expect(try atomLengths(["5368709120"]) == [5_368_709_120])
    }

    /// A server filling in a field it does not know the answer to. Shown as no size rather
    /// than as a download of nothing, which is what a reader would read a 0 KB queue row as.
    @Test func aLengthOfZeroOrLessIsNoSizeAtAll() throws {
        #expect(try atomLengths(["0", "-1"]) == [nil, nil])
    }

    /// Untrusted input: a length is a hint from a stranger, and a hint that is not a number
    /// is not a reason to lose the acquisition it was attached to.
    @Test func aLengthThatIsNotANumberLosesOnlyTheLength() throws {
        let feed = try OpdsDocument.parse(
            Data(atomSized(["not-a-number", "9e9", "12 345"]).utf8),
            baseURL: base
        )
        let acquisitions = feed.publications.first?.acquisitions ?? []
        #expect(acquisitions.count == 3)
        #expect(acquisitions.allSatisfy { $0.length == nil })
        #expect(acquisitions.allSatisfy { $0.kind == .direct })
    }

    @Test func aJsonLinkStatesItsSizeInBytes() throws {
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        #expect(feed.publications.first?.acquisitions.first?.length == 5565)
    }

    /// The two dialects spell one fact two ways, and the model has one field. A catalogue
    /// served in both — which the mock in `scripts/opds-server.mjs` is — must not report a
    /// different size depending on which one the app happened to ask for.
    @Test func bothDialectsAgreeOnOneSize() throws {
        let atom = try atomLengths(["5565"]).first ?? nil
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        #expect(atom == feed.publications.first?.acquisitions.first?.length)
    }

    @Test func aJsonSizeSentAsAStringIsNoSizeRatherThanAFailedFeed() throws {
        let body = """
        { "metadata": { "title": "t" }, "publications": [
          { "metadata": { "title": "e" },
            "links": [{ "href": "/x.epub", "type": "application/epub+zip", "size": "4096" }] } ] }
        """
        let feed = try OpdsDocument.parse(Data(body.utf8), baseURL: base)
        #expect(feed.publications.first?.title == "e")
        #expect(feed.publications.first?.acquisitions.first?.length == nil)
    }

    /// The same wrong type one field over. Found while mirroring the size tests: a quoted
    /// count failed the whole feed here and parsed fine on Android, so a catalogue that
    /// showed on one phone showed nothing on the other.
    @Test func aCountSentAsAStringCostsTheCountAndNotTheFeed() throws {
        let body = """
        { "metadata": { "title": "t" },
          "navigation": [
            { "title": "Unread", "href": "/unread", "properties": { "numberOfItems": "12" } } ] }
        """
        let feed = try OpdsDocument.parse(Data(body.utf8), baseURL: base)
        #expect(feed.navigation.map(\.title) == ["Unread"])
        #expect(feed.navigation.first?.count == nil)
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
          "metadata": { "title": "Recently added" },
          "links": [
            { "rel": "self", "href": "/opds/recent", "type": "application/opds+json" }
          ],
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
        },
        {
          "publications": [
            {
              "metadata": { "identifier": "urn:uuid:10", "title": "Untitled Group Member" },
              "links": [
                { "href": "/download/10.epub", "type": "application/epub+zip" }
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
            { "href": "/download/2.epub", "type": "application/epub+zip", "size": 5565 }
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

    @Test func aNamedGroupIsItsOwnSectionRatherThanPartOfTheRun() throws {
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        let group = try #require(feed.groups.first)
        #expect(group.title == "Recently added")
        #expect(group.publications.map(\.title) == ["Grouped Title"])
        #expect(group.navigation.map(\.title) == ["Series"])
        // What was in a group has left the feed's own run, or it would be shown twice.
        #expect(feed.navigation.map(\.title) == ["Unread"])
        #expect(!feed.publications.contains { $0.title == "Grouped Title" })
    }

    @Test func aGroupCarriesTheLinkToTheRestOfItself() throws {
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        #expect(feed.groups.first?.more?.absoluteString == "https://library.example/opds/recent")
    }

    @Test func anUnnamedGroupIsPouredIntoTheFeed() throws {
        // A section with no title is a heading nobody can read, so its contents join the
        // page rather than sitting under a blank one.
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        #expect(feed.groups.count == 1)
        #expect(feed.publications.map(\.title) == ["Harbour Lights 02", "Untitled Group Member"])
    }

    @Test func aFeedWithGroupsIsNotAnEmptyPage() throws {
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        #expect(!feed.isEmpty)
        #expect(feed.isAcquisition)

        let grouped = OpdsFeed(title: "t", groups: [OpdsGroup(title: "g", publications: [])])
        // Named but empty is still a page that says something, and still not an acquisition.
        #expect(!grouped.isEmpty)
        #expect(!grouped.isAcquisition)
        #expect(OpdsFeed(title: "t").isEmpty)
    }

    @Test func anAuthorIsReadWhicheverShapeItTakes() throws {
        let feed = try OpdsDocument.parse(Data(json.utf8), baseURL: base)
        #expect(feed.publications.first?.authors == ["Ada Lovelace", "Alan Turing"])
        #expect(feed.groups.first?.publications.first?.authors == ["Grace Hopper"])
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
