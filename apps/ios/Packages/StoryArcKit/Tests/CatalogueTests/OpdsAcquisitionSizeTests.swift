import Foundation
import Testing

@testable import Catalogue

/// What an acquisition says it costs, in both dialects.
///
/// Split out of `OpdsParsingTests` when that file crossed the 400-line cap. The size of a
/// download is one subject and earns a suite: it is a hint from a stranger that the queue
/// shows to a reader before anything is fetched, and ADR-0008 ranged reads are built on it.
struct OpdsAcquisitionSizeTests {
    private let base = OpdsFixtures.base
    private let json = OpdsFixtures.opds2

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
        let atom = try #require(atomLengths(["5565"]).first)
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
}
