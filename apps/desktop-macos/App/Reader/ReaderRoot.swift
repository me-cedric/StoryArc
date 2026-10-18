import Playback
import PlayerFeature
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

    @State private var voiceStopped = VoiceStoppedNotice.none

    var body: some View {
        reader
            .overlay(alignment: .top) {
                if let sentence = voiceStopped.sentence {
                    VoiceStoppedCapsule(sentence: sentence) { voiceStopped = voiceStopped.taken() }
                        .padding(.top, 8)
                }
            }
            .task { voiceStopped = Self.displaceVoice(opening: target) }
    }

    @ViewBuilder
    private var reader: some View {
        switch kind {
        case .epub: EpubReaderWindow(target: target, library: library)
        case .audio: PlayerWindow(target: target, library: library)
        case .pages: ReaderWindow(target: target, library: library)
        }
    }

    /// `ebook-reader`, *Opening a different publication*: a voice speaking another book ends at its sentence and
    /// records where it got to, and the window that displaced it says so once. A narrator that the opening book's
    /// own player displaced owes nothing; a word already pending from that player is taken here too. The book on the
    /// player is matched by its file as well as its id: a file the library does not list opens under another id.
    static func displaceVoice(opening target: ReaderTarget, centre: PlayerCentre = .shared) -> VoiceStoppedNotice {
        let isPlaying = centre.book?.url.standardizedFileURL == target.url.standardizedFileURL
        if !isPlaying, centre.handover(opening: target.publicationID) == .displace { centre.displace() }
        return centre.takeVoiceStopped()
    }
}
