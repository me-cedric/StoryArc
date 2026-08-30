import Foundation
import Testing

@testable import Smb

/// The server picks the name. Android's `SmbEntryNameTest` asserts the same cases in the
/// same order.
@Suite("A share entry's name as a local filename")
struct SmbEntryNameTests {
    private func entry(_ name: String) -> SmbEntry {
        SmbEntry(name: name, path: name, isDirectory: false, length: 1)
    }

    private var directory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appending(
            path: "Smb", directoryHint: .isDirectory
        )
    }

    @Test("A name full of dot segments is written under the cache, not above it")
    func dotSegmentsCannotEscape() throws {
        // The name a hostile server serves to reach the app's own preferences. The
        // decoders that need a real file are the ones that make the app write it down.
        let local = try #require(entry("../../Preferences/group.app.storyarc.plist")
            .cacheLocation(in: directory))

        #expect(local.lastPathComponent == "group.app.storyarc.plist")
        #expect(
            local.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/"),
            "wrote outside the cache directory: \(local.path)"
        )
    }

    @Test("A Windows separator is a separator too, and only the last component survives")
    func backslashIsASeparator() throws {
        // SMB's own separator. A rule that only knows about `/` is a rule the protocol
        // was never written in.
        let local = try #require(entry(#"..\..\shared_prefs\settings.xml"#)
            .cacheLocation(in: directory))

        #expect(local.lastPathComponent == "settings.xml")
        #expect(local.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/"))
    }

    @Test("A name that is nothing but dots has no last component worth keeping", arguments: [
        ".", "..", "...", "../..", "./.",
    ])
    func refusesDotOnlyNames(name: String) {
        // Refused outright rather than trimmed, the same way a download id is: trimming
        // is what invites `....//` and the rest of that family.
        #expect(entry(name).cacheLocation(in: directory) == nil)
    }

    @Test("An empty or separator-only name is refused", arguments: ["", "/", #"\"#, "//"])
    func refusesEmptyNames(name: String) {
        #expect(entry(name).cacheLocation(in: directory) == nil)
    }

    @Test("An ordinary name is left exactly as the server sent it")
    func ordinaryNameSurvives() throws {
        let local = try #require(entry("Saga 001 (2012).cbz").cacheLocation(in: directory))
        #expect(local.lastPathComponent == "Saga 001 (2012).cbz")
    }
}
