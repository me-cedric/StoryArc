public import Foundation
internal import OSLog

public import Formats
internal import Persistence
public import StoryArcCore

/// Logs an open failure; `reader.cannotOpen` is the only text a reader sees.
let readerOpenLog = Logger(subsystem: "app.storyarc.reader", category: "open")

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
        case let .unsupportedContainer(container):
            String(localized: "reader.unsupported \(container.displayName)",
                   bundle: .module.inChosenLanguage, locale: .storyArc)
        case .passwordProtected:
            String(localized: "reader.passwordProtected", bundle: .module.inChosenLanguage, locale: .storyArc)
        case .solidArchive:
            String(localized: "reader.solidArchive", bundle: .module.inChosenLanguage, locale: .storyArc)
        case .unreadable, .unrecognisedContainer:
            String(localized: "reader.damaged", bundle: .module.inChosenLanguage, locale: .storyArc)
        }
    }

    /// Whether the reader has nothing on screen for one reason or another — a real failure,
    /// or still waiting on a download. `ReaderView` draws the same chrome-stays-up behaviour
    /// for both: neither has a pager to reveal it.
    public var isBlocked: Bool { failure != nil || isWaitingForDownload }

    /// Whether a failed open at `address` should wait rather than show the ordinary failure.
    ///
    /// True only for a streamed address whose own download record has neither finished (there
    /// would be nothing to wait for — ``ReaderModel/adoptTheCopyWhenItArrives()`` would have
    /// already taken it) nor failed (`offline-downloads` asks a failed download to be "marked
    /// failed with a plain-language reason", not silently retried for ever behind a spinner).
    static func isAwaitingDownload(for address: URL, store: DownloadStore = DownloadStore()) -> Bool {
        guard ReadingAddress.isStreamed(address) else { return false }
        return store.library().downloads.contains { download in
            guard download.remote == address else { return false }
            switch download.state {
            case .queued, .running, .paused: return true
            case .finished, .failed: return false
            }
        }
    }
}
