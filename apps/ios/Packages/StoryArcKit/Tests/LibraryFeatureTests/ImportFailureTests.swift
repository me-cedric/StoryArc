import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// 10.8: an import refusal names the detected format, the same way an open-in refusal does.
@Suite("An import refusal names the format")
@MainActor
struct ImportFailureTests {
    private func store() throws -> DownloadStore {
        let name = "import-failure-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        return DownloadStore(defaults: defaults, directory: directory)
    }

    private func file(named name: String, exists: Bool = true) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "import-failure-\(UUID().uuidString)/\(name)")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if exists { try Data("not really a comic".utf8).write(to: url) }
        return url
    }

    @Test("An unsupported format is named in the failure")
    func unsupportedFormatIsNamed() async throws {
        let model = LibraryModel(downloadStore: try store())
        let url = try file(named: "notes.txt")

        await model.importFile(url)

        #expect(model.importFailure?.name == "notes.txt")
        #expect(model.importFailure?.detected == "TXT")
    }

    @Test("A file that cannot be read names no format, and nothing is imported")
    func unreadableFileNamesNoFormat() async throws {
        let model = LibraryModel(downloadStore: try store())
        let url = try file(named: "missing.cbz", exists: false)

        await model.importFile(url)

        #expect(model.importFailure?.name == "missing.cbz")
        #expect(model.importFailure?.detected == nil)
        #expect(model.publications.isEmpty)
    }

    @Test("A successful import leaves no failure behind")
    func successLeavesNoFailure() async throws {
        let model = LibraryModel(downloadStore: try store())
        let corpus = Self.corpus.appending(path: "comics/single-page.cbz")
        let url = try file(named: "single-page.cbz")
        try Data(contentsOf: corpus).write(to: url)

        await model.importFile(url)

        #expect(model.importFailure == nil)
        #expect(model.publications.count == 1)
    }

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
}
