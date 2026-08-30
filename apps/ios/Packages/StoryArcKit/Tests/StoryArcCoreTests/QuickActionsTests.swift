import Foundation
import Testing

@testable import StoryArcCore

/// The home-screen menu, asserted against the same table as Android's `QuickActionsTest`.
///
/// `native-experience` asks for quick actions on both platforms, and two independent
/// implementations (ADR-0001) only stay honest if the same cases are put to both. Add a
/// case here, add it there.
///
/// The identifiers are asserted by name at the end. They are the one part of this the two
/// platforms *share* rather than mirror: a menu already on a reader's home screen carries
/// them, so a rename is a change to stored data, not to a constant.
@Suite("Quick actions")
struct QuickActionsTests {

    private func publication(_ title: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/library/" + title),
            format: .cbz,
            displayTitle: title,
            origin: .inferred
        )
    }

    @Test("Nothing in progress and nothing downloaded leaves the library alone")
    func onlyLibrary() {
        #expect(QuickActions.offered(continuing: nil, hasDownloads: false) == [.library])
    }

    @Test("Downloads appear once there is something in them")
    func downloadsWhenThereAreSome() {
        #expect(QuickActions.offered(continuing: nil, hasDownloads: true) == [.library, .downloads])
    }

    @Test("A publication in progress is offered, and named")
    func continueIsNamed() {
        let bone = publication("Bone 1")
        let offered = QuickActions.offered(continuing: bone, hasDownloads: false)

        #expect(offered.count == 2)
        // The publication's own stable key, not its path: the entry outlives the launch
        // that published it, and the key is what the library can still be asked for.
        #expect(offered.first == .continueReading(id: bone.id, title: "Bone 1"))
    }

    @Test("Continue comes first, because it is why the icon was held down")
    func continueIsFirst() {
        let offered = QuickActions.offered(continuing: publication("Bone 1"), hasDownloads: true)

        #expect(offered.map(\.id) == [
            QuickAction.continueID, QuickAction.libraryID, QuickAction.downloadsID
        ])
    }

    @Test("A publication with nothing to call it is not offered")
    func blankTitleIsRefused() {
        // The entry's whole job is to name the book. A row headed by a blank line is one
        // a reader cannot read, and `offline-downloads` has already met such a title.
        #expect(QuickActions.offered(continuing: publication("   "), hasDownloads: false) == [.library])
    }

    @Test("A request is read back from the identifier the system stored")
    func requestsAreReadBack() {
        #expect(QuickActionRequest(id: QuickAction.libraryID) == .library)
        #expect(QuickActionRequest(id: QuickAction.downloadsID) == .downloads)
        #expect(
            QuickActionRequest(id: QuickAction.continueID, publicationID: "abc")
                == .continueReading(id: "abc")
        )
    }

    @Test("A continue entry carrying no publication is refused rather than guessed at")
    func continueWithoutAPublication() {
        #expect(QuickActionRequest(id: QuickAction.continueID) == nil)
        #expect(QuickActionRequest(id: QuickAction.continueID, publicationID: "") == nil)
    }

    @Test("An entry from an older menu is refused rather than treated as the library")
    func unknownIdentifier() {
        // A menu on a home screen can outlive the app that published it.
        #expect(QuickActionRequest(id: "app.storyarc.quickaction.widget") == nil)
        #expect(QuickActionRequest(id: "") == nil)
    }

    @Test("The three identifiers are the strings both platforms store")
    func identifiersAreTheStoredContract() {
        #expect(QuickAction.continueID == "app.storyarc.quickaction.continue")
        #expect(QuickAction.libraryID == "app.storyarc.quickaction.library")
        #expect(QuickAction.downloadsID == "app.storyarc.quickaction.downloads")
    }

    @Test("Each entry answers with its own identifier")
    func entriesCarryTheirIdentifier() {
        #expect(QuickAction.continueReading(id: "x", title: "Bone 1").id == QuickAction.continueID)
        #expect(QuickAction.library.id == QuickAction.libraryID)
        #expect(QuickAction.downloads.id == QuickAction.downloadsID)
    }
}
