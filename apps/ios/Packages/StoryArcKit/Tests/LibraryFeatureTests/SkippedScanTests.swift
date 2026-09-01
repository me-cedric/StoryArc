import Foundation
import Testing

@testable import LibraryFeature

/// A real scan of two files that fail differently, and what the library keeps of it.
///
/// The pure rules are asserted in `SkippedPublicationsTests`; this is the wiring, and it is
/// the half that was broken. `LibraryScanner` emitted `skipped(path:reason:)` from the
/// beginning; `walkFolder` matched `case .skipped:` and did nothing with it. Everything
/// above that line was correct and a reader still got a bare count.
///
/// Two corpus files that fail for **different** reasons, because one reason standing in for
/// two is exactly what the count was doing. `refused.cb7` is a container StoryArc does not
/// read; `password-protected.cbz` is a ZIP it does read whose entries it cannot. The
/// spec forbids merging them: "two files that failed differently say different things".
///
/// **`rar4-solid.cbr` is deliberately not the second file**, though the change's task list
/// names it. A solid RAR4 is *found* and marked unopenable — `LibraryScannerTests`
/// asserts that on purpose, because the library should list it and say why rather than
/// drop it — so it never reaches a skip at all.
///
/// Android asserts the same pair in `SkippedScanTest`.
@Suite("Skipped publications, from a real scan")
@MainActor
struct SkippedScanTests {

    /// Walks up from this file to the committed fixture corpus.
    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let corpus = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: corpus.appending(path: "manifest.json").path) {
                return corpus
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found — expected packages/test-fixtures above \(#filePath)")
    }()

    /// A throwaway folder holding copies of named corpus files.
    private func folder(holding files: [String]) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "skipped-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            try FileManager.default.copyItem(
                at: Self.corpus.appending(path: file),
                to: root.appending(path: (file as NSString).lastPathComponent)
            )
        }
        return root
    }

    private func model(scanning folder: URL) async -> LibraryModel {
        let model = LibraryModel(documents: folder)
        await model.rescan()
        return model
    }

    @Test("Two files that fail differently keep two different reasons")
    func twoReasonsSurviveTheScan() async throws {
        let root = try folder(holding: ["comics/refused.cb7", "comics/password-protected.cbz"])
        defer { try? FileManager.default.removeItem(at: root) }

        let model = await model(scanning: root)

        #expect(model.skipped.notice == .several(count: 2))
        #expect(Set(model.skipped.entries.map(\.name)) == ["refused.cb7", "password-protected.cbz"])
        // Not merged, and not a sentence this layer wrote: the CB7's reason names the
        // container, which is the whole point of `publication-formats` wording it.
        let reasons = Dictionary(
            uniqueKeysWithValues: model.skipped.entries.map { ($0.name, $0.reason) }
        )
        #expect(reasons["refused.cb7"]?.contains("CB7") == true)
        #expect(reasons["password-protected.cbz"] != reasons["refused.cb7"])
        #expect(model.skipped.entries.allSatisfy { !$0.reason.isEmpty })
    }

    @Test("One failure names the publication rather than counting it")
    func oneIsNamed() async throws {
        let root = try folder(holding: ["comics/refused.cb7"])
        defer { try? FileManager.default.removeItem(at: root) }

        let model = await model(scanning: root)

        guard case let .one(name, reason) = model.skipped.notice else {
            Issue.record("one refusal should name it, not count it: \(model.skipped.notice)")
            return
        }
        #expect(name == "refused.cb7")
        #expect(reason.contains("CB7"))
    }

    @Test("A scan that opens everything says nothing")
    func cleanScanIsSilent() async throws {
        let root = try folder(holding: ["comics/single-page.cbz"])
        defer { try? FileManager.default.removeItem(at: root) }

        let model = await model(scanning: root)

        #expect(model.publications.count == 1)
        #expect(model.skipped.notice == .nothing)
    }

    @Test("A second scan of the same folder does not re-announce what was dismissed")
    func secondScanIsQuiet() async throws {
        let root = try folder(holding: ["comics/refused.cb7", "comics/password-protected.cbz"])
        defer { try? FileManager.default.removeItem(at: root) }

        let model = await model(scanning: root)
        model.dismissSkipped()
        await model.rescan()

        // The library met the same two files again. Nothing changed, so nothing is said —
        // and the list is still there, which is the difference from silence.
        #expect(model.skipped.notice == .reachable)
        #expect(model.skipped.entries.count == 2)
    }

    @Test("A publication that opens on the next scan leaves the list, undismissed")
    func fixedPublicationLeavesTheList() async throws {
        let root = try folder(holding: ["comics/refused.cb7", "comics/password-protected.cbz"])
        defer { try? FileManager.default.removeItem(at: root) }

        let model = await model(scanning: root)
        #expect(model.skipped.entries.count == 2)

        // The protected archive is replaced by one that opens — a re-download, or a share
        // that came back. Nothing is dismissed; the walk is what removes it.
        try FileManager.default.removeItem(at: root.appending(path: "password-protected.cbz"))
        try FileManager.default.copyItem(
            at: Self.corpus.appending(path: "comics/single-page.cbz"),
            to: root.appending(path: "password-protected.cbz")
        )
        await model.rescan()

        #expect(model.skipped.entries.map(\.name) == ["refused.cb7"])
        guard case .one = model.skipped.notice else {
            Issue.record("one left should name it: \(model.skipped.notice)")
            return
        }
    }

    @Test("The notice goes when the last failure is fixed")
    func emptyListEndsTheNotice() async throws {
        let root = try folder(holding: ["comics/refused.cb7"])
        defer { try? FileManager.default.removeItem(at: root) }

        let model = await model(scanning: root)
        #expect(model.skipped.notice != .nothing)

        try FileManager.default.removeItem(at: root.appending(path: "refused.cb7"))
        await model.rescan()

        #expect(model.skipped.notice == .nothing)
    }
}
