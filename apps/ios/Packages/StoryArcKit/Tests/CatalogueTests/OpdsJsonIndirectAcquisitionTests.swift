import Foundation
import Testing

@testable import Catalogue

/// 11.4, read from OPDS 2.0 JSON rather than Atom: an `indirectAcquisition` property or a
/// protected media type (OPDS-LCP, Adobe ADEPT) marks a link indirect, and an unknown
/// `acquisition/*` relation is named rather than dropped.
///
/// Split out of `OpdsParsingTests`, which had reached the 400-line cap this project
/// enforces. `OpdsAtom`'s own twin of each of these lives in `OpdsParsingTests` itself.
struct OpdsJsonIndirectAcquisitionTests {
    private let base = OpdsFixtures.base

    @Test func aJsonIndirectAcquisitionPropertyMarksTheLinkIndirect() throws {
        let body = """
        { "metadata": { "title": "t" }, "publications": [
          { "metadata": { "title": "e" }, "links": [
            { "href": "/x.epub", "type": "application/epub+zip",
              "properties": { "indirectAcquisition": [{ "type": "application/vnd.readium.lcp.license.v1.0+json" }] } }
          ] } ] }
        """
        let feed = try OpdsDocument.parse(Data(body.utf8), baseURL: base)
        let acquisition = try #require(feed.publications.first?.acquisitions.first)
        #expect(acquisition.kind == .indirect)
        #expect(acquisition.mediaType == "application/epub+zip")
    }

    @Test func aJsonLcpLicenseTypeIsIndirectWithNoIndirectAcquisitionProperty() throws {
        let body = """
        { "metadata": { "title": "t" }, "publications": [
          { "metadata": { "title": "e" }, "links": [
            { "href": "/x.lcpl", "type": "application/vnd.readium.lcp.license.v1.0+json" }
          ] } ] }
        """
        let feed = try OpdsDocument.parse(Data(body.utf8), baseURL: base)
        #expect(feed.publications.first?.acquisitions.first?.kind == .indirect)
    }

    @Test func aJsonUnknownAcquisitionRelationIsIndirectRatherThanLost() throws {
        let body = """
        { "metadata": { "title": "t" }, "publications": [
          { "metadata": { "title": "e" }, "links": [
            { "href": "/x.epub", "type": "application/epub+zip",
              "rel": "http://opds-spec.org/acquisition/lend-later" }
          ] } ] }
        """
        let feed = try OpdsDocument.parse(Data(body.utf8), baseURL: base)
        #expect(feed.publications.first?.acquisitions.first?.kind == .indirect)
    }
}
