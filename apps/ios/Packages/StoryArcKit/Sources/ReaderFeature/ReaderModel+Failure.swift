public import Foundation

public import Formats
public import StoryArcCore

/// How ``ReaderModel`` names a typed archive error, rather than showing its raw case.
///
/// Split out of `ReaderModel.swift`, which had reached the 400-line cap this project
/// enforces — wording is a seam of its own, separate from the open/decode/move loop the
/// rest of that file holds.
extension ReaderModel {
    /// The same named sentence Open-in and the library already show for this container
    /// error, rather than the raw Swift case name a reader cannot read.
    ///
    /// A file that reaches the reader without going through an index first — a share row
    /// built from its name alone (`SmbContributor`), or a publication opened in the player
    /// rather than the reader — meets these errors here for the first time.
    /// `.unrecognisedContainer` falls to the catch below: reaching the reader already
    /// implies a format the library accepted, so that case is not expected here.
    static func sentence(for error: ComicArchiveError) -> String {
        switch error {
        case .unsupportedContainer:
            String(localized: "reader.unsupported", bundle: .module, locale: .storyArc)
        case .passwordProtected:
            String(localized: "reader.passwordProtected", bundle: .module, locale: .storyArc)
        case .solidArchive:
            String(localized: "reader.solidArchive", bundle: .module, locale: .storyArc)
        case .unreadable, .unrecognisedContainer:
            String(localized: "reader.damaged", bundle: .module, locale: .storyArc)
        }
    }
}
