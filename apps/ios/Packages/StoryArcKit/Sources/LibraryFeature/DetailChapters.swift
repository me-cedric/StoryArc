internal import Foundation

internal import Formats
internal import Playback
internal import StoryArcCore

/// What a chapter is called.
///
/// The rule is ``PlayerCentre``'s own, and it has to be: `AudiobookReader.read(folderAt:)`
/// writes `title: nil` for every part of a folder audiobook, so a page that only drew titles
/// would draw a column of blank rows. A part with no name of its own is numbered, never
/// blank, and never the file name — `design.md` records that last one as a product decision.
enum ChapterName: Hashable, Sendable {
    case given(String)
    /// One-based, for a part the container did not name.
    case numbered(Int)
}

/// One row of the publication page's chapter list.
struct DetailChapter: Equatable, Sendable, Identifiable {
    let index: Int
    let name: ChapterName
    /// `nil` when nothing knows how long the part runs. The row states no length rather than
    /// `0:00`, which would be a false statement about the book.
    let duration: TimeInterval?
    let mark: ChapterMark
    /// How much of this chapter is left, on the one row that is in progress, and `nil` on
    /// every other row and whenever the part's length is unknown.
    let remaining: TimeInterval?

    var id: Int { index }
}

/// Everything the publication page says about an audiobook and about nothing else.
///
/// One value rather than three properties on the column, so a page that draws a list for a
/// comic is a failing test rather than a reading of three call sites.
struct DetailAudiobook: Equatable, Sendable {
    /// Empty for a comic, for a single-part audiobook, and for a publication whose parts the
    /// device cannot read yet.
    let chapters: [DetailChapter]

    /// The whole book's length, stated where there is no list to state it.
    let length: TimeInterval?

    /// The chapter the primary action names, or `nil` for a book never started.
    let resuming: ChapterName?

    static let absent = DetailAudiobook(chapters: [], length: nil, resuming: nil)
}

extension DetailAudiobook {

    /// The rows restated from where the audio is now.
    ///
    /// **The page reads its rows once, and a remainder does not keep.** Measured on
    /// 2026-09-09: a page left open stated `18:00 left` on a chapter the audio had left twenty
    /// minutes earlier, and went on marking that chapter as the one in progress.
    /// `audio-playback` asks the same statement of "the player and the publication's page
    /// alike", and Android keeps its page live, so the two surfaces otherwise disagree by
    /// however long a listener leaves the page open.
    ///
    /// `nil` leaves every row as the stored record made it, which is the answer for every page
    /// but the one whose publication is playing.
    func restated(at place: PlaybackPlace?) -> DetailAudiobook {
        guard let place else { return self }
        return DetailAudiobook(
            chapters: chapters.map { $0.restated(at: place) },
            length: length,
            resuming: resuming
        )
    }
}

extension DetailChapter {

    /// This row, marked and counted down from where the audio is now.
    ///
    /// `isFinished: false`: audio running inside a chapter is the fact, whatever the record
    /// said before the listener started the book again.
    func restated(at place: PlaybackPlace) -> DetailChapter {
        let mark = ChapterProgress.mark(of: index, reached: place.partIndex, isFinished: false)
        return DetailChapter(
            index: index,
            name: name,
            duration: duration,
            mark: mark,
            remaining: ChapterProgress.remainder(
                ofChapterLasting: duration,
                mark: mark,
                at: place.offset
            )
        )
    }
}

/// The rules behind the publication page's chapter list.
///
/// `audio-playback`, "Chapters before the first minute": a listener choosing what to hear
/// next "could see a chapter list only by first playing something they had not chosen". The
/// player's own ``ChapterListView`` draws the same parts from the same model —
/// ``PlaybackPart``, reached here through ``PlaybackTimeline/playbackParts`` — so the two
/// lists cannot disagree about what a part is, what it is called or how long it runs.
///
/// Pure and free of SwiftUI, for the reason ``PlayerLabels`` is: each of these is a
/// requirement, and a requirement stated inside a view body is a requirement nothing checks.
enum DetailChapters {

    /// What the page draws for one publication.
    ///
    /// **The format is asked here rather than at the call site.** "A comic must not grow a
    /// chapter list" is a rule about the page, and a rule enforced by whoever remembers to
    /// write the `if` is a rule one surface will get wrong.
    static func of(
        _ format: PublicationFormat,
        parts: [PlaybackPart],
        progress: ReadingProgress?
    ) -> DetailAudiobook {
        guard format.isAudio else { return .absent }
        return DetailAudiobook(
            chapters: rows(of: parts, progress: progress),
            length: duration(of: parts),
            resuming: name(ofPartAt: place(in: progress)?.partIndex, in: parts)
        )
    }

    /// The rows, in playing order.
    ///
    /// Empty for a book of one part: "the page states the book's duration and offers no list,
    /// because a list of one row tells a listener nothing".
    static func rows(of parts: [PlaybackPart], progress: ReadingProgress?) -> [DetailChapter] {
        guard parts.count > 1 else { return [] }
        let place = place(in: progress)
        let isFinished = progress?.isFinished == true
        return parts.compactMap { part in
            guard let name = name(ofPartAt: part.index, in: parts) else { return nil }
            let mark = ChapterProgress.mark(
                of: part.index,
                reached: place?.partIndex,
                isFinished: isFinished
            )
            return DetailChapter(
                index: part.index,
                name: name,
                duration: part.duration,
                mark: mark,
                remaining: ChapterProgress.remainder(
                    ofChapterLasting: part.duration,
                    mark: mark,
                    at: place?.offset ?? 0
                )
            )
        }
    }

    /// The whole book's length, or `nil` when any part's is unknown.
    ///
    /// ``Audiobook/duration``'s rule, applied to the parts the page holds: a total assembled
    /// from some of the parts would be a number shorter than the book.
    static func duration(of parts: [PlaybackPart]) -> TimeInterval? {
        let known = parts.compactMap(\.duration)
        guard !parts.isEmpty, known.count == parts.count else { return nil }
        return known.reduce(0, +)
    }

    // MARK: - The answers each rule is built from

    /// Where the listener stopped, or `nil` for a publication never listened to.
    ///
    /// Only a listening position answers. A page position belongs to a publication that was
    /// read rather than heard, and `reading-progress` keeps one position per publication —
    /// so a comic's page index must never be read as a chapter number.
    ///
    /// The offset comes with the part because the remainder needs both, and `reading-progress`
    /// already records it: a listening position "is an offset in time within a named part".
    ///
    /// **`nil` for a finished book, which is the same guard `StoryArcApp.resumePlace(of:)`
    /// holds.** `reading-progress`: "reopening a finished publication starts at the beginning
    /// while retaining the finished record". Without it the page read the stored place of a
    /// book heard to the end, so the action promised the last chapter and the audio began at
    /// the first. Android answers null here in `ListenedPosition.resume`.
    ///
    /// The rows are unchanged by this: ``ChapterProgress/mark(of:reached:isFinished:)`` marks
    /// every chapter of a finished book finished, whatever place it is handed.
    private static func place(in progress: ReadingProgress?) -> PlaybackPlace? {
        guard progress?.isFinished != true,
              case let .listening(part, _, offset, _) = progress?.position
        else { return nil }
        return PlaybackPlace(partIndex: part, offset: offset)
    }

    /// What a part is called, by ``PlayerCentre``'s rule: its title, else its number.
    ///
    /// `nil` for the single unnamed part of a single-part book, because "Part 1 of 1" is a
    /// number a listener cannot use — and because the action on such a page offers to start
    /// the book rather than naming a chapter inside it.
    private static func name(ofPartAt index: Int?, in parts: [PlaybackPart]) -> ChapterName? {
        guard let index, parts.indices.contains(index) else { return nil }
        if let title = parts[index].title, !title.isEmpty { return .given(title) }
        guard parts.count > 1 else { return nil }
        return .numbered(index + 1)
    }
}

extension DetailChapters {

    /// Reads a publication's parts, and turns them into what the page draws.
    ///
    /// **A publication the device holds no bytes for draws no list, and reports nothing
    /// missing.** A catalogue entry that has not been downloaded has no parts to read: its
    /// chapters are a fact about a file, and a page that complained about their absence would
    /// be complaining that the reader has not downloaded the book yet.
    ///
    /// The security scope is opened around the read and closed after it — the read is the
    /// whole of the story here, unlike a session, which keeps playing the file for an hour.
    static func read(
        _ publication: Publication,
        at file: URL?,
        progress: ReadingProgress?
    ) async -> DetailAudiobook {
        guard publication.format.isAudio, let file else { return .absent }
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }

        let book = publication.format == .audioFolder
            ? await AudiobookReader.read(folderAt: file)
            : await AudiobookReader.read(fileAt: file)
        return of(
            publication.format,
            parts: PlaybackTimeline(parts: book.parts).playbackParts,
            progress: progress
        )
    }
}
