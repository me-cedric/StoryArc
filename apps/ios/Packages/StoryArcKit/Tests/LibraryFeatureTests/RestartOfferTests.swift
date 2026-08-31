import Testing

@testable import LibraryFeature

/// The rule that decides whether *Start from the beginning* is drawn. Android's
/// `RestartOfferTest` asserts the same cases.
///
/// The case that matters is `isWired`. Before it, `CoverList` opened the shelf menu with a
/// trailing closure — which binds to `onRefused`, the first parameter with no default — so
/// the restart handler stayed on its empty default and the button rendered regardless. The
/// reader tapped it and nothing happened, and nothing failed: a test asserting the button
/// exists would have passed. This asserts the opposite direction, which is the one that was
/// wrong.
@Suite("Start from the beginning is offered only when it can be delivered")
struct RestartOfferTests {
    @Test("One publication with progress and a handler is offered")
    func theOrdinaryCase() {
        #expect(
            RestartOffer.isOffered(publicationCount: 1, hasSomethingToClear: true, isWired: true)
        )
    }

    @Test("A menu with no handler draws no button")
    func unwiredIsNotOffered() {
        #expect(
            !RestartOffer.isOffered(publicationCount: 1, hasSomethingToClear: true, isWired: false)
        )
    }

    @Test("A publication with nothing to clear is not offered")
    func nothingToClear() {
        // It would start it from the beginning it is already at.
        #expect(
            !RestartOffer.isOffered(publicationCount: 1, hasSomethingToClear: false, isWired: true)
        )
    }

    @Test("A selection has no single beginning to go back to")
    func aSetIsNotOffered() {
        #expect(
            !RestartOffer.isOffered(publicationCount: 2, hasSomethingToClear: true, isWired: true)
        )
        #expect(
            !RestartOffer.isOffered(publicationCount: 0, hasSomethingToClear: true, isWired: true)
        )
    }
}
