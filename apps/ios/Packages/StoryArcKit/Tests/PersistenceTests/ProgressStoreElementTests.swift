import Foundation
import StoryArcCore
import Testing

@testable import Persistence

/// `reading-progress` O27: the store keeps a reflowable position's first visible element.
/// Android's `ProgressMigrationHostTest` asserts the same through Room.
@Suite("Progress store keeps the first visible element")
struct ProgressStoreElementTests {

    @Test("A reflowable position comes back with its element")
    func theElementComesBack() async throws {
        let store = try ProgressStore.inMemory()
        let identity = PublicationIdentity(contentDigest: "d2")
        let element = ElementLocator(
            href: "OEBPS/ch1.xhtml",
            cssSelector: "body > p:nth-child(18)",
            textBefore: "the end. ",
            textAfter: "Paragraph",
            publicationDigest: "d2"
        )
        let position = ReadingPosition.reflowable(progression: 0.5, locator: "{}", firstVisibleElement: element)

        try await store.save(ReadingProgress(identity: identity, position: position, updatedAt: .now))

        #expect(try await store.progress(for: identity)?.position == position)
    }
}
