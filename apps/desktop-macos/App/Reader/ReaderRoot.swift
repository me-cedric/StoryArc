import StoryArcCore
import SwiftUI

/// Which reader a publication opens in: the page reader for a comic, a PDF and an image
/// folder, the web view for a reflowable EPUB, the player for an audiobook.
///
/// Decided by the format the library knows, or the file's extension for a file handed over
/// before the library has it. `desktop-experience`, *The same formats on every desktop*.
/// Wave 4.
enum ReaderKind: Equatable, Sendable {
    case pages
    case epub
    case audio

    static func of(_ format: PublicationFormat) -> ReaderKind {
        if format.isAudio { return .audio }
        return format == .epub ? .epub : .pages
    }
}

/// The reader window's root: one of the three readers, by the publication's format.
struct ReaderRoot: View {
    let target: ReaderTarget
    let library: MacLibrary

    private var kind: ReaderKind {
        let format = library.model.publications.first { $0.id == target.publicationID }?.format
            ?? PublicationFormat.detected(from: target.url)
            ?? .cbz
        return ReaderKind.of(format)
    }

    var body: some View {
        switch kind {
        case .epub: EpubReaderWindow(target: target, library: library)
        case .audio: PlayerWindow(target: target, library: library)
        case .pages: ReaderWindow(target: target, library: library)
        }
    }
}
