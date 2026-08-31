import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// What a cover says out loud about the two marks a reader cannot hear.
///
/// `library-browsing` requires that a publication which cannot be opened right now "says
/// plainly that it needs its library to be reachable", and the mark for a downloaded copy
/// answers the other question a shelf is asked. Both are drawn — an opacity and a glyph in a
/// corner — and neither is audible, so both have to be in the spoken label.
///
/// The unavailability sentence rode an `accessibilityHint` before this, on the one shelf that
/// applied the dim at all. A hint is announced after the label, after the traits, and not at
/// all for a reader who has turned hints off — so the fact a reader most needs was the one
/// most likely to be dropped.
///
/// Android's `LibraryMarksTest` asserts the same three answers over the same rule.
@Suite("Library marks")
struct LibraryMarksTests {

    @Test("A cover that is readable and not downloaded says only what it draws")
    func plainCoverSaysNothingExtra() {
        #expect(
            LibraryMarks.spoken(["Ashfall #1", "Ashfall", "CBZ"], isOnDevice: false, isReadableNow: true)
                == "Ashfall #1, Ashfall, CBZ"
        )
    }

    @Test("An absent part is dropped rather than spoken as a gap")
    func absentPartsAreDropped() {
        // A publication with no series and no author has no subtitle at all, and a caller
        // must not have to compose around that: "Ashfall #1, , CBZ" is a stutter.
        #expect(
            LibraryMarks.spoken(["Ashfall #1", nil, "CBZ"], isOnDevice: false, isReadableNow: true)
                == "Ashfall #1, CBZ"
        )
    }

    @Test("A downloaded cover says so, because the mark in its corner cannot")
    func downloadedIsSpoken() {
        let spoken = LibraryMarks.spoken(["Ashfall #1"], isOnDevice: true, isReadableNow: true)

        #expect(spoken.hasPrefix("Ashfall #1, "))
        #expect(spoken != "Ashfall #1")
    }

    @Test("A publication that cannot be opened right now says so, last")
    func unavailabilityIsSpokenLast() {
        // Last on purpose: it is the exception rather than the description, and a reader
        // skimming a shelf hears the title first either way. Android appends it in the same
        // position.
        let spoken = LibraryMarks.spoken(["Ashfall #1", "CBZ"], isOnDevice: false, isReadableNow: false)

        #expect(spoken.hasPrefix("Ashfall #1, CBZ, "))
        #expect(spoken.split(separator: ", ").count == 3)
    }

    @Test("Being away is never silent, whatever else the cover has to say")
    func bothMarksCanBeSpokenAtOnce() {
        // The pair cannot both be true of one publication today — bytes on the device are
        // what makes it readable — but the rule must not depend on that, because it is the
        // download store and the source registry that decide, and they are two stores.
        let spoken = LibraryMarks.spoken(["Ashfall #1"], isOnDevice: true, isReadableNow: false)

        #expect(spoken.split(separator: ", ").count == 3)
    }

    @Test("One opacity for Home and the shelf")
    func oneAwayOpacity() {
        // Two numbers is what shipped: 0.45 on the sectioned shelf and 0.55 on Home, so a
        // reader moving between the two screens saw the same book at two brightnesses.
        #expect(LibraryMarks.awayOpacity == 0.45)
    }
}

/// That the dim and the mark reach every layout, not just the one shelf that used to apply
/// them.
///
/// The rule was handed to ``SectionedShelf`` and to nothing else, and that shelf is only
/// drawn for a grid of more than twelve items — so a short library, every search result and
/// the whole list layout drew an unreachable publication at full brightness. The cell asks
/// the rule itself now, which is what makes "every layout" assertable at all.
@Suite("Marks reach every layout")
@MainActor
struct ShelfMarkReachTests {

    private func awayLibrary() -> (LibraryModel, Publication) {
        var source = Source(displayName: "Attic", kind: .networkShare)
        source.state = .unreachable(since: .now)
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: "/remote/away.cbz"),
            format: .cbz,
            displayTitle: "Away",
            origin: .inferred,
            sourceID: source.id
        )
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [source])
        model.publications = [publication]
        // No location: the bytes are on the share, and the share is not answering.
        return (model, publication)
    }

    @Test("A cover in the grid knows it is away without being told")
    func gridCellAsksTheRuleItself() {
        let (model, publication) = awayLibrary()

        #expect(
            !CoverCell(publication: publication, model: model, maxPixelSize: 200)
                .isReachableNow
        )
    }

    @Test("A row in the list answers the same question the same way")
    func listRowAsksTheSameRule() {
        // The layout toggle is a display choice. Until this, it also decided whether the
        // shelf told you which of your books would open on a train.
        let (model, publication) = awayLibrary()

        #expect(
            !ListRow(
                publication: publication,
                model: model,
                thumbnailWidth: 44,
                maxPixelSize: 132
            ).isReachableNow
        )
    }

    @Test("A publication whose library is answering is drawn at full brightness in both")
    func reachablePublicationsAreNotDimmed() {
        var source = Source(displayName: "Attic", kind: .opdsCatalog)
        source.state = .connected
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: "/remote/here.cbz"),
            format: .cbz,
            displayTitle: "Here",
            origin: .inferred,
            sourceID: source.id
        )
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [source])
        model.publications = [publication]

        #expect(CoverCell(publication: publication, model: model, maxPixelSize: 200).isReachableNow)
        #expect(
            ListRow(publication: publication, model: model, thumbnailWidth: 44, maxPixelSize: 132)
                .isReachableNow
        )
    }
}
