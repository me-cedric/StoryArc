import SwiftUI
import Testing

import DesignSystem
@testable import LibraryFeature
import StoryArcCore

/// A downloaded Kavita title states its status and its rating, and takes no room when it has
/// neither to state.
///
/// `kavita-server`: "when a downloaded Kavita publication is opened with the server
/// unreachable, the cached server metadata is displayed, not the file's embedded metadata".
/// The other five fields that requirement names reach the page through
/// `KavitaCard.applied(to:)` and are asserted where that is; these two cannot — `Publication`
/// has no slot for either — so this is the only place on iOS that says they are drawn at all.
///
/// **Measured rather than predicated.** The claim is about layout, and every cheaper way of
/// putting it passes on the defect: a view that returns an empty `VStack` when there is no
/// card satisfies "draws no text", satisfies "has no status", and still leaves
/// `StoryArcSpace.xl` of nothing under the description of every publication that never came
/// from a Kavita server — which is most of the shelf. So the assertions here are heights
/// taken from `ImageRenderer`, in the stack the page actually composes.
///
/// Android's `KavitaCardFactsTest` makes the same four claims through Robolectric.
@Suite("Kavita card facts")
@MainActor
struct KavitaCardFactsTests {

    /// Kavita's own numbers: 10 is `Mature 17+` and 2 is `Completed`.
    private static let statedRating = 10
    private static let statedStatus = 2

    private func card(ageRating: Int, publicationStatus: Int) -> KavitaCard {
        KavitaCard(
            publicationId: "p1",
            downloadId: "d1",
            sourceId: "s",
            seriesId: 7,
            chapterId: 1,
            seriesName: "Tidal Reach",
            chapterName: "The Harbour",
            ageRating: ageRating,
            publicationStatus: publicationStatus
        )
    }

    /// A card kept from a server that stated both.
    private var stating: KavitaCard {
        card(ageRating: Self.statedRating, publicationStatus: Self.statedStatus)
    }

    /// The two values a card written before these fields existed comes back with, and the two
    /// a keep from a server that stated neither writes down.
    private var silent: KavitaCard { card(ageRating: 0, publicationStatus: -1) }

    // MARK: - Measuring

    private func height<Content: View>(of content: Content, width: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(content: content.frame(width: width))
        var measured = CGSize.zero
        renderer.render { size, _ in measured = size }
        return measured.height
    }

    /// The description and the block under it, stacked the way the page stacks them.
    private func underADescription(_ card: KavitaCard?) -> CGFloat {
        height(
            of: VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                Text(verbatim: "A harbour town, described by the file it came in.")
                KavitaCardFacts(card: card)
            },
            width: 320
        )
    }

    /// The same stack with the block left out entirely, which is the floor everything that
    /// says nothing has to come back to.
    private var descriptionAlone: CGFloat {
        height(
            of: VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                Text(verbatim: "A harbour town, described by the file it came in.")
            },
            width: 320
        )
    }

    // MARK: - The two lines

    @Test("The status and the rating the card kept are both drawn")
    func bothLinesAreDrawn() {
        // Each is a named line rather than a bare value, which is the whole reason they do
        // not join the run of facts: "Mature 17+" alone reads as a genre.
        let block = height(of: KavitaCardFacts(card: stating), width: 320)
        let statusOnly = height(
            of: KavitaCardFacts(card: card(ageRating: 0, publicationStatus: Self.statedStatus)),
            width: 320
        )
        let ratingOnly = height(
            of: KavitaCardFacts(card: card(ageRating: Self.statedRating, publicationStatus: -1)),
            width: 320
        )

        // One line each, so the two are independent: a block that drew only the first would
        // measure the same for both single cases and for the pair.
        #expect(statusOnly > 0)
        #expect(statusOnly == ratingOnly)
        #expect(block > statusOnly)

        // And the pair is inside the page's stack, one spacing slot below the description.
        #expect(underADescription(stating) == descriptionAlone + StoryArcSpace.xl + block)
    }

    // MARK: - Nothing to say is nothing at all

    @Test("A card that stated neither leaves no room behind")
    func aSilentCardTakesNoRoom() {
        // Zero is Kavita's `Unknown` rating and -1 is outside its status table. Drawing
        // either would state something no server said; reserving room for them is the other
        // half of the same mistake, and the half a text assertion cannot see.
        #expect(underADescription(silent) == descriptionAlone)
    }

    @Test("A publication with no card at all leaves no room behind")
    func noCardTakesNoRoom() {
        // Most of the shelf: a file in a picked folder has no Kavita card, and 24 pt of
        // nothing under its description would be the page reserving room for a server it
        // never had.
        #expect(underADescription(nil) == descriptionAlone)
    }

    // MARK: - The wiring

    @Test("The page's column draws them, not just the block on its own")
    func theColumnDrawsThem() {
        // The wiring, which is where the defect would live. `KavitaCardFacts` drawing two
        // lines proves nothing if the page never calls it, and deleting that one call leaves
        // every other test in this file green. Android composes `DetailMainPane` for the same
        // reason; `DetailMainColumn` is the seam that lets iOS mirror it.
        let block = height(of: KavitaCardFacts(card: stating), width: 360)
        #expect(
            height(of: column(kavitaCard: stating), width: 360)
                == height(of: column(kavitaCard: nil), width: 360) + StoryArcSpace.xl + block
        )
    }

    private func column(kavitaCard: KavitaCard?) -> DetailMainColumn {
        DetailMainColumn(
            publication: downloaded,
            model: LibraryModel(),
            cover: nil,
            isKept: .constant(true),
            kavitaCard: kavitaCard,
            file: nil,
            onRead: {}
        )
    }

    /// A downloaded publication, whose own `id` the card is filed under.
    private var downloaded: Publication {
        Publication(
            identity: PublicationIdentity(contentDigest: "p1"),
            format: .cbz,
            displayTitle: "The Harbour",
            series: "Tidal Reach",
            summary: "A harbour town, described by the file it came in.",
            origin: .authoritative
        )
    }
}
