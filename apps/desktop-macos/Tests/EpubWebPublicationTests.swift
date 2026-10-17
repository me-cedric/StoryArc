import Formats
import Foundation
import Testing

@testable import StoryArc

/// The Readium Web Publication Manifest and the positions the Mac builds in Swift from
/// `Formats`, against the corpus `packages/test-fixtures/manifest.json` pins. Open Question 6
/// of `desktop-clients`: the positions follow the rule every platform shares, the compressed
/// entry size in kilobytes rounded up and at least one, so the core's `epub_positions.rs`
/// and this suite assert the same numbers for the same books. Task 4.5.
@Suite("EPUB web publication")
struct EpubWebPublicationTests {
    static let selfHref = "storyarc-epub://book/manifest.json"

    @Test("The fixture's manifest carries its spine, contents, metadata and cover as the corpus pins them")
    func fixtureManifest() async throws {
        let built = try await EpubWebPublication.build(
            url: TestFixtures.ebooks.appending(path: "fixture.epub"), selfHref: Self.selfHref
        )
        let manifest = built.manifest
        #expect(manifest.metadata.title == "Fixture Publication")
        #expect(manifest.metadata.author == "StoryArc Fixtures")
        #expect(manifest.metadata.language == ["en"])
        #expect(manifest.metadata.identifier == "urn:uuid:storyarc-fixture-0001")
        #expect(manifest.metadata.layout == "reflowable")
        #expect(manifest.metadata.readingProgression == "auto")
        #expect(manifest.readingOrder.map(\.href) == ["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"])
        #expect(manifest.readingOrder.map(\.type) == ["application/xhtml+xml", "application/xhtml+xml"])
        #expect(manifest.toc.map(\.title) == ["Chapter One", "Chapter Two"])
        #expect(manifest.readingOrder.map(\.title) == ["Chapter One", "Chapter Two"])
        #expect(manifest.resources.map(\.href) == ["OEBPS/cover.png"])
        #expect(manifest.resources.first?.rel == "cover")
        #expect(manifest.links == [EpubWebLink(href: Self.selfHref, type: "application/webpub+json", rel: "self")])
    }

    @Test("The fixture's positions are one per small spine item, numbered from one across the book")
    func fixturePositions() async throws {
        let built = try await EpubWebPublication.build(
            url: TestFixtures.ebooks.appending(path: "fixture.epub"), selfHref: Self.selfHref
        )
        #expect(built.positionCounts == [1, 1])
        #expect(built.positions.map(\.locations.position) == [1, 2])
        #expect(built.positions.map(\.locations.totalProgression) == [0, 0.5])
        #expect(built.positions.map(\.locations.progression) == [0, 0])
        #expect(built.positions.map(\.href) == ["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"])
    }

    @Test("The positions rule: compressed kilobytes rounded up, at least one", arguments: [
        (Int64(0), 1), (Int64(1), 1), (Int64(1024), 1), (Int64(1025), 2),
        (Int64(10 * 1024), 10), (Int64(10 * 1024 + 1), 11),
    ])
    func positionRule(size: Int64, count: Int) {
        #expect(EpubWebPublication.positionCount(compressedSize: size) == count)
    }

    @Test("Every corpus book builds, with one position per spine item and a total progression that climbs")
    func corpus() async throws {
        let names = ["fixture", "epub2", "series", "one-sentence", "fixed-layout", "spine-cover", "declared-rtl"]
        for name in names {
            let built = try await EpubWebPublication.build(
                url: TestFixtures.ebooks.appending(path: "\(name).epub"), selfHref: Self.selfHref
            )
            #expect(!built.manifest.readingOrder.isEmpty, Comment(rawValue: name))
            #expect(built.positions.count == built.positionCounts.reduce(0, +), Comment(rawValue: name))
            let totals = built.positions.map(\.locations.totalProgression)
            #expect(totals == totals.sorted(), Comment(rawValue: name))
            #expect(totals.first == 0, Comment(rawValue: name))
        }
    }

    @Test("An EPUB 2 reads its NCX contents, a fixed-layout book says so, and a declared direction wins")
    func renditions() async throws {
        let epub2 = try await EpubWebPublication.build(
            url: TestFixtures.ebooks.appending(path: "epub2.epub"), selfHref: Self.selfHref
        )
        #expect(epub2.manifest.toc.map(\.title) == ["Premier chapitre", "Second chapitre"])
        #expect(epub2.manifest.metadata.language == ["fr"])
        let fixed = try await EpubWebPublication.build(
            url: TestFixtures.ebooks.appending(path: "fixed-layout.epub"), selfHref: Self.selfHref
        )
        #expect(fixed.manifest.metadata.layout == "fixed")
        let rtl = try await EpubWebPublication.build(
            url: TestFixtures.ebooks.appending(path: "declared-rtl.epub"), selfHref: Self.selfHref
        )
        #expect(rtl.manifest.metadata.readingProgression == "rtl")
        #expect(rtl.manifest.toc.isEmpty)
    }

    @Test("The JSON the renderer reads names its context, its self link and its positions")
    func json() async throws {
        let built = try await EpubWebPublication.build(
            url: TestFixtures.ebooks.appending(path: "fixture.epub"), selfHref: Self.selfHref
        )
        let manifest = try #require(try JSONSerialization.jsonObject(with: built.manifestData()) as? [String: Any])
        #expect(manifest["@context"] as? String == "https://readium.org/webpub-manifest/context.jsonld")
        let metadata = try #require(manifest["metadata"] as? [String: Any])
        #expect(metadata["@type"] as? String == "http://schema.org/Book")
        let positions = try #require(try JSONSerialization.jsonObject(with: built.positionsData()) as? [[String: Any]])
        #expect(positions.count == 2)
        let locations = try #require(positions[1]["locations"] as? [String: Any])
        #expect(locations["position"] as? Int == 2)
    }

    @Test("A book that is not an EPUB is refused by the reader, not served")
    func notAnEpub() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await EpubWebPublication.build(
                url: TestFixtures.comics.appending(path: "natural-sort.cbz"), selfHref: Self.selfHref
            )
        }
    }
}
