import Foundation
import Testing

/// That a handed-over file whose streaming is `refused` is refused before the reader opens
/// it, rather than after.
///
/// `publication-formats`: a solid RAR4 indexes as an *opened* record, with streaming
/// `refused` rather than a thrown `IndexError` — the library lists it and says why. Open-in
/// has no library row to show it in, so `OpenedFile.index(_:)` has to ask `isOpenable`
/// itself before handing a publication to the reader.
///
/// **This reads the app's source text**, for the reason ``ShellWiringTests`` and
/// ``RefusedFileWordingTests`` both give: the app target has no test target of its own, and
/// `swift test` runs this package alone. Android's `OpenedFileOutcomeTest` asserts the same
/// outcome with a real JVM test target and real fixture bytes, which this file cannot reach.
@Suite("Opened-file wiring")
struct OpenedFileWiringTests {
    private static let appDirectory: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory.appendingPathComponent("App")
    }()

    private func source(_ file: String) throws -> String {
        let path = Self.appDirectory.appendingPathComponent(file).path
        return try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read — has \(file) moved?"
        )
    }

    @Test("A publication that is not openable is named before it reaches the reader")
    func notOpenableIsCaughtBeforeTheReader() throws {
        let text = try source("OpenedFile.swift")
        #expect(
            text.contains("publication.isOpenable"),
            """
            OpenedFile.index(_:) no longer asks `publication.isOpenable`. A solid RAR4 opens \
            as a record with streaming `refused` rather than throwing, and without this \
            check it would reach `.opened` and be sent straight to a reader that cannot \
            render page one.
            """
        )
    }

    @Test("Every refusal StoryArcAppActions switches on is a case this file can return")
    func everyCaseIsHandled() throws {
        let outcomes = try source("OpenedFile.swift")
        let actions = try source("StoryArcAppActions.swift")
        for name in ["passwordProtected", "damaged", "solidArchive"] {
            #expect(outcomes.contains("case \(name)"), "OpenedFile.Outcome has no `.\(name)` case.")
            #expect(actions.contains(".\(name):"), "StoryArcAppActions does not switch on `.\(name)`.")
        }
    }
}
