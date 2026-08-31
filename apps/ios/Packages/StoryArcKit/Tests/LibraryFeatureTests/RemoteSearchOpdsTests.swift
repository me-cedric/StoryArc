import Foundation
import Testing

@testable import Catalogue
@testable import LibraryFeature
@testable import StoryArcCore

/// The photographed defect, reproduced from the server's own bytes and then fixed.
///
/// On 2026-08-31 a reader searched *Fine Print* on a device with a catalogue and a local
/// folder configured. `scripts/opds-server.mjs` logged `200 GET /opds/all?q=Fine%20Print` —
/// so the catalogue was asked and answered — and not one of its results reached the screen.
/// The capture is `docs/designs/screenshots/after-2026-08-31/ios-search-remote-and-away-dark.png`.
///
/// The feed below is the exact acquisition document that server returns for that query, so
/// the dialect under test is the one the app was actually driven against rather than a
/// hand-written idea of it. Parsed, turned into rows, and merged with what the device holds.
///
/// The fetch itself is not re-proved here: `OpdsClientTests` covers it against a `URLProtocol`
/// stub, and registering a second one from this target would intercept that suite's requests.
/// Android's `RemoteSearchOpdsTest` drives the same outcome through a real server on the
/// loopback interface, which is the half this cannot reach.
@Suite("Remote search over OPDS")
struct RemoteSearchOpdsTests {

    private let base = URL(string: "http://127.0.0.1:4444/opds/all")!

    private let catalogue = Source(displayName: "StoryArc Test Catalogue", kind: .opdsCatalog)

    /// `scripts/opds-server.mjs`'s answer to `/opds/all?q=Fine%20Print`, verbatim.
    private let searchFeed = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom"
          xmlns:opds="http://opds-spec.org/2010/catalog"
          xmlns:thr="http://purl.org/syndication/thread/1.0">
      <id>urn:storyarc:All publications</id>
      <title>All publications — “Fine Print”</title>
      <link rel="self" href="/opds/all" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
      <link rel="up" href="/opds" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
      <entry>
        <id>urn:storyarc:4</id>
        <title>Fine Print</title>
        <updated>2026-08-30T11:52:01Z</updated>
        <author><name>Ada Lovelace</name></author>
        <summary>A test publication, application/vnd.comicbook+zip.</summary>
        <link rel="http://opds-spec.org/image" href="/covers/Fine%20Print.cbz" type="image/png"/>
        <link rel="http://opds-spec.org/acquisition"
              href="/files/Fine%20Print.cbz" type="application/vnd.comicbook+zip"/>
      </entry>
    </feed>
    """

    private func answered() throws -> [FoundRow] {
        let feed = try OpdsDocument.parse(Data(searchFeed.utf8), baseURL: base)
        return FoundRow.away(
            RemoteSearch.catalogueRows(feed.publications, from: catalogue),
            from: catalogue
        )
    }

    @Test("What the catalogue answers becomes a row that names the catalogue")
    func rowsCarryTheCatalogue() throws {
        let rows = try answered()
        #expect(rows.map(\.result.title) == ["Fine Print"])
        #expect(rows.map(\.origin) == [
            .library(id: catalogue.id.uuidString, name: "StoryArc Test Catalogue")
        ])
        // Not a publication the library holds, so it leads to the catalogue rather than to
        // the publication page — which resolves against the library's own set and would open
        // on "this one is gone".
        #expect(rows.allSatisfy { $0.result.publicationID == nil })
        #expect(rows.first?.result.route?.sourceID == catalogue.id.uuidString)
    }

    @Test("The catalogue's answer reaches the list beside the copy on the device")
    func mergedBesideTheLocalCopy() throws {
        // The defect, as a case. Before this change both rows folded to one and the reader
        // was shown only what the device held, with nothing on screen to say a catalogue had
        // answered at all.
        let onDevice = FoundRow(
            result: SearchResult(
                kind: .publication,
                title: "Fine Print",
                publicationID: "held:fine-print"
            ),
            origin: .library(id: "folder", name: "Attic NAS")
        )
        let listing = SearchListing(
            term: "Fine Print",
            namesOrigin: true,
            local: [onDevice],
            asking: [catalogue.id.uuidString]
        )
        .answered(catalogue.id.uuidString, with: try answered())

        #expect(listing.rows.map(\.result.title) == ["Fine Print", "Fine Print"])
        #expect(listing.rows.map(\.origin) == [
            .library(id: "folder", name: "Attic NAS"),
            .library(id: catalogue.id.uuidString, name: "StoryArc Test Catalogue")
        ])
        // One heading, not two: the rows are merged into one ranked list, and what separates
        // them is the label rather than a section per answerer.
        #expect(listing.groups.map(\.kind) == [.publication])
    }

    @Test("The term is escaped the way both platforms escape it")
    @MainActor
    func oneQuestionNotTwoSpellings() throws {
        // `scripts/opds-server.mjs` advertises `/opds/all?q={searchTerms}` inline, and its
        // log recorded `GET /opds/all?q=Fine%20Print` arriving. That is this substitution.
        let filled = CatalogueBrowser.fill("/opds/all?q={searchTerms}", with: "Fine Print")
        #expect(filled?.absoluteString == "/opds/all?q=Fine%20Print")
    }
}
