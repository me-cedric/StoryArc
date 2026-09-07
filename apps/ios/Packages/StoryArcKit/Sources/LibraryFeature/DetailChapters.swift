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

/// Where the listener is, relative to one chapter.
enum ChapterMark: Equatable, Sendable {
    case unplayed
    case inProgress
    case finished
}

/// One row of the publication page's chapter list.
struct DetailChapter: Equatable, Sendable, Identifiable {
    let index: Int
    let name: ChapterName
    /// `nil` when nothing knows how long the part runs. The row states no length rather than
    /// `0:00`, which would be a false statement about the book.
    let duration: TimeInterval?
    let mark: ChapterMark

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
            resuming: name(ofPartAt: reached(in: progress), in: parts)
        )
    }

    /// The rows, in playing order.
    ///
    /// Empty for a book of one part: "the page states the book's duration and offers no list,
    /// because a list of one row tells a listener nothing".
    static func rows(of parts: [PlaybackPart], progress: ReadingProgress?) -> [DetailChapter] {
        guard parts.count > 1 else { return [] }
        let reached = reached(in: progress)
        let isFinished = progress?.isFinished == true
        return parts.compactMap { part in
            guard let name = name(ofPartAt: part.index, in: parts) else { return nil }
            return DetailChapter(
                index: part.index,
                name: name,
                duration: part.duration,
                mark: mark(of: part.index, reached: reached, isFinished: isFinished)
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

    /// The part the listener stopped inside, or `nil` for a publication never listened to.
    ///
    /// Only a listening position answers. A page position belongs to a publication that was
    /// read rather than heard, and `reading-progress` keeps one position per publication —
    /// so a comic's page index must never be read as a chapter number.
    private static func reached(in progress: ReadingProgress?) -> Int? {
        guard case let .listening(part, _, _, _) = progress?.position else { return nil }
        return part
    }

    /// Behind the listener, under them, or ahead.
    private static func mark(of index: Int, reached: Int?, isFinished: Bool) -> ChapterMark {
        // A book recorded finished has no chapter left ahead of the listener, whatever
        // position it stopped writing at.
        if isFinished { return .finished }
        guard let reached else { return .unplayed }
        if index < reached { return .finished }
        return index == reached ? .inProgress : .unplayed
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
