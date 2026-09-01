public import Foundation

/// What a walk makes of audio it finds.
///
/// Two questions, both about the *shelf-or-publication* decision `LibraryScanner` makes per
/// directory: whether a file counts as audio at all, and whether a directory holding some is
/// itself an audiobook. Split out of `LibraryScanner.swift` when they pushed it past the
/// 400-line cap; the seam is real, because both are about audio and nothing else in that
/// file is.
extension LibraryScanner {
    /// Whether a file is a candidate part or a candidate audiobook.
    ///
    /// **Audio is deliberately not in ``candidateExtensions``.** Putting it there would make
    /// every part of a folder of chapter MP3s its own publication, which is the one thing
    /// `publication-formats` says a folder of audio is not — "a folder holds ordered audio
    /// files … it is treated as a single audiobook". So audio is counted separately, exactly
    /// as images already are, and the folder-versus-file decision below reads both.
    ///
    /// The set itself is `FolderKind`'s, so the walk and the kind cannot disagree about what
    /// counts as audio.
    static func isAudio(_ url: URL) -> Bool {
        FolderKind.audioExtensions.contains(url.pathExtension.lowercased())
    }

    /// Whether a directory holding audio *is* an audiobook rather than a shelf with one on it.
    ///
    /// **The subdirectory clause is a regression fix and it was found by a screenshot.**
    /// Without it, one `.m4b` sitting beside a library's own folders made the whole library
    /// a single audiobook: the picked folder held no packed publication at its top level —
    /// they were all one directory down — so the audio branch claimed it, its subdirectories
    /// were never walked, and a shelf of fifteen comics became one row reading "Audio
    /// folder". Every unit test passed; the shelf in the picture did not lie.
    ///
    /// A folder of ordered audio has no subdirectories, and a folder that has them is a place
    /// where publications live. The audio at its top level is still indexed — file by file,
    /// one book each — by the loop below.
    ///
    /// The image branch keeps its own rule untouched, where subdirectories *are* chapters of
    /// the comic. That asymmetry is real: a comic's pages are commonly split into chapter
    /// folders and an audiobook's parts are not.
    static func isAudiobookFolder(_ audio: [URL], _ directories: [URL]) -> Bool {
        !audio.isEmpty && directories.isEmpty
    }
}
