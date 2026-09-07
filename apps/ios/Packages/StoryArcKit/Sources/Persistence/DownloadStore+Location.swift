import Foundation

/// Where a download's bytes actually are, which is not always where the name says.
///
/// Its own file rather than another member of ``DownloadStore``, for the reason
/// `PublicationIndexer+Audiobook.swift` gives about its own parent: `DownloadStore.swift`
/// is at the 400-line cap, and this is a question of its own — the store computes a path
/// from a record, and this reconciles that with the filesystem.
extension DownloadStore {

    /// The file this download's folder actually holds under `stem`, whatever its extension.
    ///
    /// **The extension is computed, and a computed name can change under a file that did
    /// not.** Every audio media type fell to the `bin` default until 2026-09-07, because no
    /// audio type mapped to a format. Giving audio its media types renamed the *computed*
    /// path from `Title.bin` to `Title.mp3` and renamed nothing on disk, so every audiobook
    /// downloaded by an earlier build would have stopped opening, kept its on-device mark,
    /// and gone on being counted by ``bytesOnDisk()`` with nothing able to remove it.
    ///
    /// The stem has to match. A download's folder also holds its resume token, and a
    /// fallback that took the only file it found would hand a reader the token.
    ///
    /// The extension alone comes back, and the caller rebuilds the path. `contentsOfDirectory`
    /// resolves a symbolic link, so on macOS it answers under `/private/var` where the
    /// computed path says `/var`. Both name one file and the two strings are not equal, and a
    /// caller comparing them would see a mismatch that is not there.
    static func extensionOnDisk(stem: String, in folder: URL) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        ) else { return nil }
        return entries.first { $0.deletingPathExtension().lastPathComponent == stem }?.pathExtension
    }
}
