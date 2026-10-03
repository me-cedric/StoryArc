import Formats
import Foundation
import StoryArcCore
import Testing

@testable import LibraryFeature

/// Why a refused publication does not open, as the shelf and the share browser say it.
///
/// `publication-formats` gives two refusals two different reasons. A solid RAR4 "uses solid
/// compression". A CB7 is a container StoryArc does not read, and the app "states which
/// formats it does support" rather than a generic failure. `SmbContributor` refuses a CB7 row
/// from its name alone, so the cell, the list row and the publication page must not call it
/// solid. Android's `DetailActionsTest` and `RefusalWordingTest` make the same claims.
@Suite("Why a refused publication does not open")
struct RefusalSentenceTests {
    private func refused(_ format: PublicationFormat) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/refused"),
            format: format,
            displayTitle: "Refused",
            origin: .inferred,
            streaming: .refused
        )
    }

    @Test("A CB7 is refused by its container, never as solid compression")
    func cb7NamesItsContainer() {
        let sentence = refused(.cb7).refusalSentence
        #expect(sentence.contains("CB7"), "\(sentence) does not name CB7.")
        #expect(sentence.contains("CBZ"), "\(sentence) names no format StoryArc reads.")
        #expect(!sentence.contains("solid"), "\(sentence) blames solid compression.")
    }

    @Test("A solid RAR4 is refused by its compression")
    func solidNamesItsCompression() {
        #expect(refused(.cbr).refusalSentence.contains("solid compression"))
    }

    @MainActor
    @Test("The share browser's unsupported sentence lists the formats StoryArc reads")
    func shareUnsupportedListsFormats() async {
        var said: LocalizedStringResource?
        await ShareOpening.offerOrOpen(
            file: ("Lantern Green 043.cb7", 10),
            index: { throw PublicationIndexer.IndexError.unsupported(format: "7-Zip") },
            onOpen: { _, _ in },
            onOffer: { _ in },
            onSay: { said = $0 }
        )
        let sentence = said.map { String(localized: $0) } ?? ""
        #expect(sentence.contains("CBZ"), "\(sentence) names no format StoryArc reads.")
    }
}
