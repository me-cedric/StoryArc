import Foundation
import Testing

@testable import StoryArcCore

/// Where a cover may be written back, and — the point of the suite — where it may not.
///
/// Task 5.2 of `cover-for-every-publication` asks for a test that no write action appears
/// anywhere else, "so the feature cannot drift into offering a 403". The subject enum is
/// exhaustive, so a later row has to pick a case and this suite has to be told about it.
struct CoverWriteBackTests {
    @Test("A reading list the reader owns is offered the write")
    func offersAnOwnedReadingList() {
        let offer = CoverWriteBack.offer(for: .kavitaReadingList(id: 7, promoted: false))
        #expect(offer == .kavitaReadingList(id: 7))
    }

    @Test("A promoted reading list is not, because it may belong to anybody")
    func refusesAPromotedReadingList() {
        // `ReadingList/lists` answers with the reader's own lists plus the promoted ones, so
        // promoted is the only case where the answer does not prove ownership.
        #expect(CoverWriteBack.offer(for: .kavitaReadingList(id: 7, promoted: true)) == .none)
    }

    @Test("No Kavita entity but a reading list is offered a write")
    func refusesEveryAdminOnlyKavitaRoute() {
        // Five of Kavita's six cover routes need the administrator role. An action that
        // exists and answers 403 teaches a reader that the app is broken.
        let admin: [CoverWriteSubject] = [
            .kavitaSeries, .kavitaChapter, .kavitaCollection, .kavitaLibrary,
        ]
        for subject in admin {
            #expect(CoverWriteBack.offer(for: subject) == .none)
        }
    }

    @Test("No OPDS row is offered a write, in either version of the protocol")
    func refusesOpds() {
        // OPDS has no write operation in 1.2 or 2.0. Not a missing feature: an absent
        // concept.
        #expect(CoverWriteBack.offer(for: .opds) == .none)
    }

    @Test("A file on this device has nowhere to write to")
    func refusesALocalFile() {
        #expect(CoverWriteBack.offer(for: .localFile) == .none)
    }
}
