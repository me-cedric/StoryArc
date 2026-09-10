import Catalogue
import Foundation
import StoryArcCore
import Testing

@testable import LibraryFeature

/// What one entry of a catalogue looks like as a row.
///
/// The one thing this must not do is keep an acquisition address: `sources` forbids a
/// cached catalogue holding a credential, and an OPDS acquisition link can carry a key in
/// its query. Android's `OpdsContributorTest` makes the same claims.
struct OpdsContributorTests {

    private let source = UUID()

    private func entry(
        id: String = "urn:uuid:1",
        title: String = "Tidal Reach",
        series: String? = nil,
        index: Double? = nil,
        type: String? = "application/vnd.comicbook+zip"
    ) -> OpdsEntry {
        OpdsEntry(
            id: id,
            title: title,
            series: series,
            seriesIndex: index,
            acquisitions: type.map {
                [
                    OpdsAcquisition(
                        href: URL(string: "https://example/get?key=secret")!,
                        mediaType: $0,
                        kind: .open
                    ),
                ]
            } ?? []
        )
    }

    @Test("An entry is identified by its catalogue and its own id")
    func identity() {
        let row = OpdsContributor.publication(source: source, entry: entry())

        #expect(row?.identity.serverIdentifier?.sourceID == source)
        #expect(row?.identity.serverIdentifier?.remoteID == "opds:urn:uuid:1")
        #expect(row?.identity.normalizedPath == nil)
    }

    @Test("No acquisition address survives into the row")
    func noSecret() {
        let row = OpdsContributor.publication(source: source, entry: entry())
        let written =
            [row?.displayTitle, row?.series, row?.number, row?.summary,
             row?.identity.serverIdentifier?.remoteID, row?.identity.normalizedPath]
            .compactMap { $0 } + (row?.authors ?? [])

        #expect(written.allSatisfy { !$0.contains("secret") })
    }

    @Test("A navigation entry is not a publication")
    func navigation() {
        #expect(OpdsContributor.publication(source: source, entry: entry(type: nil)) == nil)
    }

    @Test("An entry the app cannot open is not listed")
    func unopenable() {
        let row = OpdsContributor.publication(
            source: source,
            entry: entry(type: "application/x-mobipocket")
        )

        #expect(row == nil)
    }

    @Test("Each media type files under a format the filter can show")
    func formats() {
        func format(_ type: String) -> PublicationFormat? {
            OpdsContributor.publication(source: source, entry: entry(type: type))?.format
        }

        #expect(format("application/vnd.comicbook+zip") == .cbz)
        #expect(format("application/vnd.comicbook-rar") == .cbr)
        // An EPUB is a zip and says so; the comic branch matching first filed every book
        // on every catalogue as a comic.
        #expect(format("application/epub+zip") == .epub)
        #expect(format("application/pdf") == .pdf)
    }

    @Test("A series index reads as an issue number")
    func numbers() {
        #expect(OpdsContributor.publication(source: source, entry: entry(index: 3))?.number == "3")
        #expect(
            OpdsContributor.publication(source: source, entry: entry(index: 3.5))?.number == "3.5"
        )
    }
}
