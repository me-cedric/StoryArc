import Foundation
import Testing

@testable import LibraryFeature
import Formats
import StoryArcCore

/// A remote PDF on the publication page is fetched whole, with progress, then opened.
///
/// Task 14.15 and O4. `publication-formats`, *Opening a remote PDF on iOS*: the app "fetches
/// the whole file first, shows how far the fetch has come, and opens the PDF reader when it
/// ends", and "a fetch that fails is stated as a connection failure, not as a fault in the
/// file". ``ShareReadTests`` pins that the page asks for the fetch. This drives the fetch.
@MainActor
@Suite("A remote PDF is fetched whole before it opens")
struct ShareFetchTests {

    private static let share = URL(string: "smb://nas/comics/Field%20Notes.pdf")
        ?? URL(fileURLWithPath: "/Field Notes.pdf")

    private static let pdf = Publication(
        identity: PublicationIdentity(normalizedPath: share.absoluteString),
        format: .pdf,
        displayTitle: "Field Notes",
        origin: .inferred,
        streaming: .downloadOnly,
        fileSize: 9_000_000
    )

    /// Nine megabytes: more than two chunks, so the progress moves more than once.
    private static let bytes = Data((0..<9_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })

    private static func folder() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ShareFetchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// What the fetch reported, from whichever task it reported on.
    private final class Steps: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Double] = []
        var values: [Double] { lock.withLock { stored } }
        func append(_ value: Double) { lock.withLock { stored.append(value) } }
    }

    private struct Outcome {
        var opened: URL?
        var said: LocalizedStringResource?
    }

    private func fetch(
        from source: @escaping () async throws -> any RandomAccessSource,
        at address: URL = share,
        into directory: URL,
        progress: Steps = Steps()
    ) async -> Outcome {
        var outcome = Outcome()
        await ShareFetch.fetch(
            Self.pdf,
            at: address,
            into: directory,
            source: source,
            progress: { fraction in progress.append(fraction) },
            onOpen: { _, local in outcome.opened = local },
            onSay: { outcome.said = $0 }
        )
        return outcome
    }

    @Test("The whole file lands on the device and opens from there")
    func fetchesWholeThenOpens() async throws {
        let directory = Self.folder()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outcome = await fetch(from: { DataSource(Self.bytes) }, into: directory)

        let local = try #require(outcome.opened, "the PDF never opened: \(String(describing: outcome.said))")
        #expect(local.isFileURL)
        #expect(local.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(local.lastPathComponent == "Field Notes.pdf")
        #expect(try Data(contentsOf: local) == Self.bytes)
        #expect(outcome.said == nil)
    }

    @Test("The fetch reports how far it has come, from nought to the whole")
    func reportsProgress() async {
        let directory = Self.folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = Steps()

        _ = await fetch(from: { DataSource(Self.bytes) }, into: directory, progress: progress)

        let steps = progress.values
        #expect(steps.first == 0)
        #expect(steps.last == 1)
        #expect(steps.count > 2, "only \(steps) was reported, so the bar would jump")
        #expect(steps == steps.sorted(), "progress went backwards: \(steps)")
    }

    @Test("A share that cannot be reached is said as a connection failure, and nothing opens")
    func anUnreachableShareIsAConnectionFailure() async {
        struct Unreachable: Error {}
        let directory = Self.folder()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outcome = await fetch(from: { throw Unreachable() }, into: directory)

        #expect(outcome.opened == nil)
        #expect(outcome.said?.key == ShareOpening.unexpected.key)
    }

    @Test("A fetch that breaks half way is said the same way, and leaves no file behind")
    func aBrokenFetchLeavesNothing() async throws {
        struct Dropped: Error {}
        struct DroppingSource: RandomAccessSource {
            let length: Int64 = 9_000_000
            func read(offset: Int64, count: Int) async throws -> Data {
                if offset > 0 { throw Dropped() }
                return Data(repeating: 0, count: count)
            }
        }
        let directory = Self.folder()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outcome = await fetch(from: { DroppingSource() }, into: directory)

        #expect(outcome.opened == nil)
        #expect(outcome.said?.key == ShareOpening.unexpected.key)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(left.isEmpty, "a broken fetch left \(left)")
    }

    @Test("A name that is a place is refused rather than written outside the folder")
    func aNameThatIsAPlaceIsRefused() async {
        let directory = Self.folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hostile = URL(string: "smb://nas/comics/..") ?? Self.share

        let outcome = await fetch(from: { DataSource(Self.bytes) }, at: hostile, into: directory)

        #expect(outcome.opened == nil)
        #expect(outcome.said?.key == ShareOpening.unexpected.key)
    }

    @Test("The page routes a fetch answer to the fetch, not to the offer")
    func thePageFetches() {
        let page = LibraryFeatureSource.code(of: "Sources/LibraryFeature/PublicationDetailView.swift")
        #expect(page.contains("case .fetch: await fetchShare(share)"))
        #expect(page.contains("ShareFetch.fetch("))
        #expect(page.contains("ShareFetchBar("))
    }
}
