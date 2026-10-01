import Catalogue
import Foundation
import Testing

@testable import LibraryFeature

/// What the grid's caption says about a catalogue entry it cannot offer as a download.
///
/// `opds-catalog` requires a refusal to be named rather than silent, and names two
/// different refusals: a format the app has no decoder for, and an acquisition kind
/// (a loan, a purchase, a subscription) the app does not follow at all. 11.6: before,
/// both read as the first — the raw media type — which told a reader an EPUB could not
/// be opened when the truth was that this one could only be borrowed.
struct CatalogueEntryCellTests {

    private func entry(mediaType: String, kind: OpdsAcquisition.Kind) -> OpdsEntry {
        OpdsEntry(
            id: "urn:uuid:1",
            title: "Tidal Reach",
            authors: ["Ada Lovelace"],
            acquisitions: [
                OpdsAcquisition(
                    href: URL(string: "https://example/get")!,
                    mediaType: mediaType,
                    kind: kind
                ),
            ]
        )
    }

    @Test("A loan-only EPUB names the loan, not the format")
    func loanOnly() {
        let caption = CatalogueEntryCell.subtitle(for: entry(mediaType: "application/epub+zip", kind: .borrow))

        #expect(caption.contains("StoryArc cannot follow"))
        #expect(!caption.contains("epub"))
    }

    @Test("A format with no decoder still names the format")
    func unreadableFormat() {
        let caption = CatalogueEntryCell.subtitle(for: entry(mediaType: "application/x-mobipocket", kind: .open))

        #expect(caption.contains("StoryArc cannot open"))
    }

    @Test("An entry offering nothing at all says so")
    func nothingOffered() {
        let caption = CatalogueEntryCell.subtitle(for: OpdsEntry(id: "urn:uuid:2", title: "Empty"))

        #expect(caption == String(localized: "catalogue.entry.noDownload", bundle: .module, locale: .storyArc))
    }

    @Test("A readable entry names the series or the author instead")
    func readable() {
        let caption = CatalogueEntryCell.subtitle(
            for: entry(mediaType: "application/epub+zip", kind: .open)
        )

        #expect(caption == "Ada Lovelace")
    }
}
