import Foundation
import Testing

@testable import StoryArc

/// Opening files, task 2.18: the batch limit, the CB7 refusal by name, and a recent item
/// whose file vanished leaving the list silently.
@Suite("Open requests")
struct OpenRequestTests {
    static var fixtures: URL { TestFixtures.comics }

    @Test("Several files open up to the limit and the rest are listed")
    func batchLimit() {
        let urls = (1...9).map { URL(filePath: "/comics/\($0).cbz") }

        let plan = OpenBatch.plan(urls, limit: 6)

        #expect(plan.open.count == 6)
        #expect(plan.listed.map(\.lastPathComponent) == ["7.cbz", "8.cbz", "9.cbz"])
        #expect(OpenBatch.plan([], limit: 6) == OpenBatch.Plan(open: [], listed: []))
    }

    @Test("A CB7 archive is refused by name, and a readable file beside it still opens")
    func cb7IsRefused() async {
        let cb7 = Self.fixtures.appending(path: "refused.cb7")
        let cbz = Self.fixtures.appending(path: "natural-sort.cbz")

        let refused = await MacOpenedFile.index(cb7)
        let opened = await MacOpenedFile.index(cbz)

        #expect(refused == .unsupported(detected: "CB7"))
        if case let .opened(publication) = opened {
            #expect(publication.pageCount == 12)
        } else {
            Issue.record("natural-sort.cbz did not open: \(opened)")
        }
    }

    @Test("A file that cannot be reached is named as unreadable")
    func missingFile() async {
        let outcome = await MacOpenedFile.index(URL(filePath: "/Volumes/Away/gone.cbz"))
        #expect(outcome == .unreadable)
    }

    @Test("A vanished file leaves the recent list silently, newest stays first, five at most")
    func recentItems() throws {
        let name = "mac-recent-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let recents = RecentPublications(defaults: defaults) { !$0.path.contains("gone") }

        for id in ["a", "b", "gone", "c", "d", "e", "f"] {
            recents.note(ReaderTarget(publicationID: id, path: "/comics/\(id).cbz", title: id))
        }
        recents.note(ReaderTarget(publicationID: "c", path: "/comics/c.cbz", title: "c"))

        let listing = recents.listing()

        #expect(listing.map(\.publicationID) == ["c", "f", "e", "d"])
        #expect(!listing.contains { $0.publicationID == "gone" })
        #expect(listing.count <= RecentPublications.limit)
    }
}
