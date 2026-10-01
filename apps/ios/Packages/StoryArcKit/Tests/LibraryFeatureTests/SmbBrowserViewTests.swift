import Testing

@testable import LibraryFeature
import StoryArcCore

/// That a share row's own headers, once read, are never read a second time.
///
/// `publication-formats` asks the format, the page count, the cover and the streaming state
/// from a row's own headers to reach it as it nears the viewport -- and a tap on that same row
/// has to use what the viewport already found rather than opening the headers again. Android's
/// `SmbBrowserScreenTest` asserts the same case.
@Suite("A share row's headers are read once")
@MainActor
struct SmbBrowserViewTests {

    private func publication(_ path: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: path),
            format: .cbz,
            displayTitle: path,
            origin: .inferred
        )
    }

    @Test("A path indexed once is cached, and read again on a second call")
    func cachedSecondCall() async throws {
        var reads = 0
        let first = try await cachedOrIndexed(cached: nil) {
            reads += 1
            return publication("comics/Bone.cbz")
        }
        let second = try await cachedOrIndexed(cached: first) {
            reads += 1
            return publication("comics/Bone.cbz")
        }

        #expect(reads == 1)
        #expect(first.id == second.id)
    }

    @Test("Two different paths are indexed once each")
    func twoPathsEachOnce() async throws {
        var reads = 0
        _ = try await cachedOrIndexed(cached: nil) {
            reads += 1
            return publication("comics/Bone.cbz")
        }
        _ = try await cachedOrIndexed(cached: nil) {
            reads += 1
            return publication("comics/Fables.cbz")
        }

        #expect(reads == 2)
    }
}
