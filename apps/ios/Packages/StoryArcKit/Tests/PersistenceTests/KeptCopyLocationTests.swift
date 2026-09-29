import Foundation
import Testing

@testable import Persistence

/// Where a copy kept off a share lands, whatever the share called the file.
///
/// `keptForOffline` used to write to `directory.appending(path: remote.lastPathComponent)`.
/// `lastPathComponent` decodes percent escapes, so a share entry named
/// `..%2F..%2FLibrary%2Fx.cbz` resolved outside the download directory. The copy is now named
/// by ``DownloadStore/location(for:mediaType:title:in:)``, the rule every other download writer
/// uses, and this pins that the rule keeps a hostile name inside the directory.
@Suite("A kept copy stays inside the download directory")
struct KeptCopyLocationTests {
    private let directory = URL.temporaryDirectory
        .appending(path: "kept-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func isInside(_ file: URL) -> Bool {
        file.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
    }

    @Test(
        "A title that names a way out of the directory stays in it",
        arguments: ["../../Library/x", "..%2F..%2FLibrary%2Fx", "/etc/passwd", "..", "a/../../b"]
    )
    func hostileTitleStaysInside(_ title: String) {
        let file = DownloadStore.location(
            for: "urn:storyarc:1", mediaType: "application/vnd.comicbook+zip", title: title, in: directory
        )
        #expect(isInside(file), "\(title) resolved to \(file.standardizedFileURL.path)")
        #expect(file.deletingLastPathComponent().lastPathComponent == "urn-storyarc-1")
    }

    @Test("An identity that names a way out of the directory stays in it")
    func hostileIdentityStaysInside() {
        let file = DownloadStore.location(
            for: "smb://nas/Comics/../../x", mediaType: "application/vnd.comicbook+zip", title: "x", in: directory
        )
        #expect(isInside(file), "resolved to \(file.standardizedFileURL.path)")
    }
}
