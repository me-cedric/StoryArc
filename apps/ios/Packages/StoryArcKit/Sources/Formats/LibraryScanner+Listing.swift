public import Foundation

public import StoryArcCore

/// What a folder holds, read without opening any of it.
///
/// Split out of `LibraryScanner.swift` for the reason `LibraryScanner+Audio.swift` was — the
/// 400-line cap — and the seam is real: listing a folder and walking it answer different
/// questions. One compares a folder against what was already scanned; the other opens
/// containers and decides what they are.
extension LibraryScanner {
    /// What a folder holds, without opening anything in it.
    ///
    /// The cheap half of `local-library`'s watched changes: the app "reconciles by comparing
    /// file modification times and sizes rather than re-reading every archive". A directory
    /// listing is one call per folder; opening an archive is hundreds of reads, and a
    /// reconcile that opened them all would be the full rescan the requirement forbids.
    ///
    /// The same decisions as ``scan(folderAt:known:skipping:onUnreadableFolder:)`` — the same
    /// extensions, and the same a-folder-of-images-is-one-publication rule — because the two
    /// lists are compared against each other. A disagreement would make the same publication
    /// appear and disappear on every pass.
    ///
    /// **This one still cannot say whether it read the folder**, which the walk now can. An
    /// unreadable folder lists nothing here and reads as a folder whose every publication has
    /// gone. Left as it is deliberately: nothing compares a snapshot without having just
    /// walked the same folder, so the walk's own answer covers the case — and closing it here
    /// as well means a second return value on a function whose callers only want the rows.
    public static func entries(in folder: URL) -> [FolderSnapshot.Entry] {
        var found: [FolderSnapshot.Entry] = []
        list(folder, into: &found)
        return found
    }

    private static func list(_ directory: URL, into found: inout [FolderSnapshot.Entry]) {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var files: [URL] = []
        var directories: [URL] = []
        for child in children {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            if isDirectory { directories.append(child) } else { files.append(child) }
        }

        let publications = files.filter {
            candidateExtensions.contains($0.pathExtension.lowercased())
        }
        let images = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        let audio = files.filter { isAudio($0) }
        // The same rule the walk uses, and it has to be the same one: `local-library`
        // reconciles a returning app by comparing this listing against what was scanned, and
        // a listing that called a folder one publication where the walk called it a shelf
        // would report every publication in it as gone on every launch. `LibraryScannerTests`
        // asserts the two agree, and caught exactly that.
        if publications.isEmpty, !images.isEmpty || isAudiobookFolder(audio, directories) {
            found.append(entry(for: directory))
            return
        }
        // A lone audiobook beside packed comics is its own row. It is not in
        // `candidateExtensions` on purpose — see that property's own note.
        for file in publications + audio { found.append(entry(for: file)) }
        for child in directories { list(child, into: &found) }
    }

    /// One listing row. A folder of images has no size of its own, so it is compared on its
    /// modification date alone — which is what changes when a page is added to it.
    private static func entry(for url: URL) -> FolderSnapshot.Entry {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return FolderSnapshot.Entry(
            path: normalized(url),
            modified: values?.contentModificationDate ?? .distantPast,
            size: Int64(values?.fileSize ?? 0)
        )
    }
}
