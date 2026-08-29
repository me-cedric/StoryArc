import Foundation
import Testing

@testable import Catalogue

/// Which format an entry opens as, and what the reader is offered instead.
///
/// `opds-catalog`: "the app selects EPUB for reflowable reading and lets the user choose
/// another format from the publication detail screen", and an entry with nothing readable is
/// "listed but marked unreadable, naming the formats offered". Both halves are decided here
/// rather than on the screen, so the screen has nothing to get wrong.
struct CatalogueAcquisitionTests {
    /// An entry offering each media type in turn, as a plain acquisition.
    private func entry(_ types: [String]) throws -> OpdsEntry {
        try entry(types.map { ($0, OpdsAcquisition.Kind.direct) })
    }

    private func entry(_ offers: [(String, OpdsAcquisition.Kind)]) throws -> OpdsEntry {
        var acquisitions: [OpdsAcquisition] = []
        for (position, offer) in offers.enumerated() {
            let href = try #require(URL(string: "https://library.example/get/\(position)"))
            acquisitions.append(
                OpdsAcquisition(href: href, mediaType: offer.0, kind: offer.1)
            )
        }
        return OpdsEntry(id: "urn:uuid:1", title: "The Long Field", acquisitions: acquisitions)
    }

    @Test func epubIsChosenWhereverItSitsInTheFeed() throws {
        let offered = try entry(["application/pdf", "application/epub+zip"])
        #expect(CatalogueAcquisition.best(of: offered)?.mediaType == "application/epub+zip")
    }

    @Test func aComicIsPreferredToThePdfCopyOfIt() throws {
        // A comic offered as both CBZ and PDF is a comic, and the PDF is a worse copy.
        let offered = try entry(["application/pdf", "application/vnd.comicbook+zip"])
        #expect(CatalogueAcquisition.best(of: offered)?.mediaType == "application/vnd.comicbook+zip")
    }

    @Test func theChoiceIsOfferedBestFirst() throws {
        let offered = try entry([
            "application/pdf",
            "application/vnd.comicbook+zip",
            "application/epub+zip",
        ])
        #expect(
            CatalogueAcquisition.readable(in: offered).map(\.mediaType) == [
                "application/epub+zip",
                "application/vnd.comicbook+zip",
                "application/pdf",
            ]
        )
    }

    @Test func twoOfOneFormatKeepTheOrderTheFeedListedThemIn() throws {
        // `sorted` is not stable, so equal ranks are tie-broken by position on purpose:
        // which of two EPUBs opens by default must not change between runs.
        let offered = try entry(["application/epub+zip", "application/epub+zip"])
        let choice = CatalogueAcquisition.readable(in: offered)
        #expect(choice.first?.href == offered.acquisitions.first?.href)
    }

    @Test func aTypeWithParametersIsStillThatType() throws {
        // Several servers append `;charset=utf-8`, and an exact-match table called that
        // unreadable.
        let offered = try entry(["application/epub+zip;charset=utf-8"])
        #expect(CatalogueAcquisition.best(of: offered) != nil)
        #expect(CatalogueAcquisition.unreadable(in: offered).isEmpty)
    }

    @Test func aFormatWithNoDecoderIsNamedRatherThanOffered() throws {
        // `publication-formats` leaves 7-Zip undecoded. The entry is listed, the refusal
        // names the format, and nothing pretends it can be opened.
        let offered = try entry(["application/vnd.comicbook+7z"])
        #expect(CatalogueAcquisition.best(of: offered) == nil)
        #expect(CatalogueAcquisition.unreadable(in: offered) == ["CB7"])
    }

    @Test func anUnknownMediaTypeIsNamedVerbatim() throws {
        let offered = try entry(["application/x-mobipocket-ebook"])
        #expect(CatalogueAcquisition.unreadable(in: offered) == ["application/x-mobipocket-ebook"])
    }

    @Test func oneFormatOfferedTwiceIsNamedOnce() throws {
        let offered = try entry(["application/x-mobi", "application/x-mobi"])
        #expect(CatalogueAcquisition.unreadable(in: offered).count == 1)
    }

    @Test func aBorrowIsRefusedByName() throws {
        // `opds-catalog`: an indirect acquisition makes the app "state that the acquisition
        // type is not supported rather than failing silently". Neither readable nor
        // unreadable — it is a flow this app does not have, which is a different sentence.
        let offered = try entry([("application/epub+zip", OpdsAcquisition.Kind.borrow)])
        #expect(CatalogueAcquisition.readable(in: offered).isEmpty)
        #expect(CatalogueAcquisition.unreadable(in: offered).isEmpty)
        #expect(CatalogueAcquisition.unsupported(in: offered) == [.borrow])
    }

    @Test func eachRefusedKindIsStatedOnceAndInFeedOrder() throws {
        let offered = try entry([
            ("application/epub+zip", OpdsAcquisition.Kind.buy),
            ("application/pdf", OpdsAcquisition.Kind.buy),
            ("application/epub+zip", OpdsAcquisition.Kind.borrow),
        ])
        #expect(CatalogueAcquisition.unsupported(in: offered) == [.buy, .borrow])
    }

    @Test func anEntryOfferingNothingIsOfferedNothing() {
        let offered = OpdsEntry(id: "urn:uuid:2", title: "Nothing At All")
        #expect(CatalogueAcquisition.best(of: offered) == nil)
        #expect(CatalogueAcquisition.readable(in: offered).isEmpty)
        #expect(CatalogueAcquisition.unreadable(in: offered).isEmpty)
        #expect(CatalogueAcquisition.unsupported(in: offered).isEmpty)
    }

    @Test func aSampleIsSomethingToFetch() throws {
        let offered = try entry([("application/epub+zip", OpdsAcquisition.Kind.sample)])
        #expect(CatalogueAcquisition.best(of: offered) != nil)
    }
}
