import Foundation
import Testing

/// `sources`' corrected note for task 22.1: a server added during a session used to join the
/// library only at the next pull or launch, because `LibraryModel.add` wrote the registry and
/// nothing asked the new source for anything. Each of the three add-a-source sheets now reads
/// every server right after adding one.
///
/// Read as source, for the reason `WhatsNewWiringTests` gives: driving the three sheets end to
/// end needs a live `LibraryModel`, credentials and a presented sheet, which `swift test` has
/// no simulator to compose.
@Suite("Add-a-source starts a read wiring")
struct AddSourceStartsAReadWiringTests {

    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.appleRoot.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    @Test("Each add-a-source sheet reads every server right after adding")
    func eachSheetReadsAfterAdding() throws {
        let code = try source("Packages/StoryArcKit/Sources/LibraryFeature/AddingSources.swift")
        let calls = code.components(separatedBy: "{ added($0) }").count - 1
        let explanation = "AddingSources.swift calls added($0)" +
            " \(calls) time(s); expected 3 (the catalogue, Kavita and share sheets)."
        #expect(calls == 3, "\(explanation)")
        let added = "model.add(source, credentials: CredentialStore())\n        Task { await model.readServers() }"
        #expect(code.contains(added), "added(_:) does not read every server after adding.")
    }
}
