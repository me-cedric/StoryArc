import Formats
import LibraryFeature
import Testing

@testable import StoryArc

extension WindowWalks {
    /// What a folder scan could not open, over the fixture library in the app.
    ///
    /// `library-browsing`, *What could not be opened*: the fixture folder holds a 7-Zip
    /// archive, a password-protected one and a solid RAR, so the scan has several to report,
    /// counted in the notice and each named with its reason in the list behind it; dismissing
    /// the notice leaves the list reachable.
    @MainActor
    @Suite("Skipped walk")
    struct SkippedWalkTests {
        @Test("Several publications a scan could not open are counted, named with reasons, and stay reachable")
        func skippedAreReported() async throws {
            let library = try await Walk.fixtureLibrary()
            let skipped = library.model.skipped

            let names = Set(skipped.entries.map(\.name))
            #expect(names.isSuperset(of: ["refused.cb7", "password-protected.cbz"]), "skipped: \(names)")
            let cb7 = try #require(skipped.entries.first { $0.name == "refused.cb7" })
            #expect(cb7.reason == .unsupportedFormat("CB7"), "refused.cb7 was skipped as \(cb7.reason)")
            if case let .several(count) = skipped.notice {
                #expect(count == skipped.entries.count)
            } else if skipped.notice != .reachable {
                Issue.record("the notice is \(skipped.notice), not a count")
            }

            library.model.dismissSkipped()
            #expect(library.model.skipped.notice == .reachable)
            #expect(library.model.skipped.entries.count == skipped.entries.count)
        }
    }
}
