import Foundation
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

/// Task 3.14, test first: the diagnostic saved to a file the reader names.
///
/// `desktop-experience`, *Exporting a diagnostic to a file*: the export is shown, a save
/// dialog asks where, and a file is written there; a place that cannot be written is named
/// and another offered, with nothing written elsewhere; a cancel writes nothing and keeps
/// nothing. Every credential, token and host is redacted as on a phone.
@MainActor
@Suite("Diagnostic export")
struct DiagnosticExportTests {
    private let folder = URL.temporaryDirectory
        .appending(path: "diagnostic-\(UUID().uuidString)", directoryHint: .isDirectory)

    private var registry: SourceRegistry {
        SourceRegistry().adding(Source(
            displayName: "nas", kind: .networkShare, state: .connected,
            credentialReference: "ref", locator: "smb://reader:hunter2secret@nas.example.org:4745/Comics"
        ))
    }

    private func text() -> String {
        MacDiagnostic.text(
            settings: AppSettings(), sources: registry, cacheBytes: 1_024, historyBytes: 2_048,
            extra: [
                "lastWriteFailure = smb://reader:hunter2secret@nas.example.org:4745/Comics",
                "token=abcdef0123456789abcdef",
            ]
        )
    }

    @Test("Saving writes the export, whole, where the reader chose")
    func saving() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let chosen = folder.appending(path: "StoryArc diagnostic.txt")
        let exporter = DiagnosticExporter(choose: { chosen })
        let outcome = await exporter.export(text())
        #expect(outcome == .saved(chosen))
        let written = try String(contentsOf: chosen, encoding: .utf8)
        #expect(written == text())
        #expect(written.contains("[Sources]"))
    }

    @Test("A place that cannot be written is named, and nothing is written anywhere else")
    func unwritable() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = folder.appending(path: "gone/StoryArc diagnostic.txt")
        let exporter = DiagnosticExporter(choose: { missing })
        let outcome = await exporter.export(text())
        #expect(outcome == .failed(place: "gone"))
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(left.isEmpty, "something was written beside the place that failed: \(left)")
    }

    @Test("A cancel writes nothing, and nothing of the export is kept")
    func cancelling() async throws {
        var wrote = false
        let exporter = DiagnosticExporter(choose: { nil }, write: { _, _ in wrote = true })
        #expect(await exporter.export(text()) == .cancelled)
        #expect(!wrote)
    }

    @Test("Every credential, token and host is redacted, as on a phone")
    func redacted() {
        let export = text()
        for secret in ["hunter2secret", "nas.example.org", "abcdef0123456789abcdef", "reader:"] {
            #expect(!export.contains(secret), "\(secret) survived the redaction")
        }
        #expect(export.contains("platform = macOS"))
        #expect(export.contains("configured = 1"))
    }
}
