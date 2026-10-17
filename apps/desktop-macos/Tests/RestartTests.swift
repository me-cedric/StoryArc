import Foundation
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

/// `reading-progress`, *Restart deliberately*: *Start from the beginning* is on a cover's
/// own menu, offered only on one publication that has a position to clear, and it clears
/// the position only once the reader confirms.
@Suite("Restart from the beginning")
struct RestartOfferTests {
    @Test("Offered on one publication with progress, never on a set, an unread one or with no store")
    func offered() {
        #expect(RestartRequest.isOffered(hasProgress: true, selectionCount: 1, hasStore: true))
        #expect(!RestartRequest.isOffered(hasProgress: false, selectionCount: 1, hasStore: true))
        #expect(!RestartRequest.isOffered(hasProgress: true, selectionCount: 3, hasStore: true))
        #expect(!RestartRequest.isOffered(hasProgress: true, selectionCount: 1, hasStore: false))
    }

    @Test("The menu counts the whole selection only when the clicked cover is part of it")
    func selectionCount() {
        let selection = LibrarySelection().clicked("a").commandClicked("b")
        #expect(RestartRequest.menuCount(for: "a", in: selection) == 2)
        #expect(RestartRequest.menuCount(for: "c", in: selection) == 1)
        #expect(RestartRequest.menuCount(for: "a", in: LibrarySelection()) == 1)
    }
}

extension WindowWalks {
    @MainActor
    @Suite("Restart walk")
    struct RestartWalkTests {
        @Test("Starting over asks first, a cancel keeps the place, and a confirm clears it")
        func confirmThenClear() async throws {
            let library = try await Walk.fixtureLibrary()
            let publication = try #require(Walk.publication(named: "stored-entries", in: library))
            let store = try #require(library.progress)
            try await store.save(ReadingProgress(
                identity: publication.identity, position: .page(index: 2, of: 3), updatedAt: Date()
            ))
            await library.refreshProgress()
            #expect(library.record(of: publication) != nil)

            library.requestRestart(publication)
            #expect(library.restartRequest?.publication.id == publication.id)
            library.cancelRestart()
            #expect(library.restartRequest == nil)
            #expect(library.record(of: publication) != nil, "a cancel cleared the place")

            library.requestRestart(publication)
            await library.confirmRestart()
            #expect(library.restartRequest == nil)
            #expect(library.record(of: publication) == nil, "the place survived the confirm")
            #expect(try await store.progress(for: publication.identity) == nil)
        }
    }
}
