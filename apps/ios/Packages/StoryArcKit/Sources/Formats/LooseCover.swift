public import Foundation

/// A cover image that sits *beside* a publication rather than inside it.
///
/// Task 1.2 of `cover-for-every-publication`, and the `cover-art` ladder's second rung: "the
/// file carries no artwork, and a `cover`, `folder` or `poster` image sits in the same folder,
/// or in an audiobook's own folder". It is the cheapest rung after the bytes themselves —
/// nothing is decoded to find it and nothing leaves the device — and it is what a folder
/// ripped from a CD or exported by a media server almost always already carries.
///
/// ``AudiobookCover/inFolder(at:)`` asked the same question for audiobook folders alone, under
/// six hard-coded names. The names live here now so one rung answers for every format, and so
/// `poster` — which Jellyfin and Plex write and which the earlier list did not know — is found
/// by the shelf as well as by the player.
public enum LooseCover {

    /// The stems a loose cover is looked for under, in the order they are tried.
    ///
    /// `cover` first because it is what this app's own export writes, then `folder`, which is
    /// the Windows Media and Kodi convention, then `poster`, which is Jellyfin's and Plex's.
    public static let stems = ["cover", "folder", "poster"]

    /// The extensions each stem is tried with, in the order they are tried.
    ///
    /// Every one of these is a format ``PageDecoder`` already decodes, so a name found here
    /// can always be drawn. A `.gif` or a `.bmp` beside a book is far likelier to be an
    /// illustration than a cover, which is why the list stops where it does.
    public static let fileExtensions = ["jpg", "jpeg", "png", "webp", "heic"]

    /// Every name tried, stem by stem, extension within stem.
    ///
    /// Stem outermost on purpose: a folder holding both `cover.png` and `folder.jpg` means
    /// the first, and a reader who wrote `cover.png` should not be answered with the picture
    /// their media server left behind.
    public static let fileNames: [String] = stems.flatMap { stem in
        fileExtensions.map { "\(stem).\($0)" }
    }

    /// A loose cover inside `url`, which is a folder.
    ///
    /// For an audiobook folder, an image folder, or any other publication that *is* a
    /// directory — the picture lives among the parts rather than next to them.
    public static func inFolder(at url: URL) -> URL? {
        for name in fileNames {
            let candidate = url.appending(path: name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// A loose cover for the publication stored at `url`, whether `url` is a file or a folder.
    ///
    /// A folder is searched; a file's own directory is searched. The two cases are one rung
    /// rather than two because the reader does not experience them as different: the picture
    /// is "the one next to the book", and whether the book is a file or a folder of files is
    /// the container's business.
    public static func beside(_ url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        return inFolder(at: isDirectory.boolValue ? url : url.deletingLastPathComponent())
    }
}
