import Testing

@testable import LibraryFeature

/// What a Kavita shelf's card draws on the home surface, decided from what the server
/// answered — the field report's own order: the server's own cover, then the first
/// members', then a named blank.
struct HomeServerShelfCoverTests {

    @Test("The server's own locked cover wins, whatever else came back")
    func lockedCoverWins() {
        #expect(HomeShelfCoverPlan.decide(hasLockedCover: true, memberIDs: []) == .sole)
        #expect(HomeShelfCoverPlan.decide(hasLockedCover: true, memberIDs: ["1", "2"]) == .sole)
    }

    @Test("With no locked cover, the first members composite")
    func membersComposite() {
        #expect(
            HomeShelfCoverPlan.decide(hasLockedCover: false, memberIDs: ["7", "3", "9", "1"])
                == .composite(["7", "3", "9", "1"])
        )
    }

    @Test("Nothing answered at all draws the named blank")
    func nothingAnsweredIsBlank() {
        #expect(HomeShelfCoverPlan.decide(hasLockedCover: false, memberIDs: []) == .blank)
    }
}
