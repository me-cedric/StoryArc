import Foundation

/// A chapter's start in a publication, and its own name when the marker carries one.
struct ChapterMarker: Equatable, Sendable {
    let index: Int
    let title: String?
}

/// What the page browser names above itself for a page.
enum ChapterLabel: Equatable, Sendable {
    case named(String)
    case position(Int)

    var text: String {
        switch self {
        case let .named(name): name
        case let .position(number): String(localized: "desktop.chapter.number \(number)")
        }
    }
}

/// Chapters, for the chapter actions, the page browser and the slider's ticks.
///
/// `comic-reader`, *Chapter navigation* and *Page browser*. The markers are `ComicInfo`'s
/// `Bookmark` pages, which `Formats` reads (`ComicArchiveReading.chapterStartIndices` and
/// `chapterTitles`). The rules are Mac copies of `ChapterNavigation` and `ChapterBrowser`,
/// internal to `ReaderFeature` (parent edit, task 5.12's family); `ReaderChaptersTests`
/// holds them to the iOS cases.
enum ReaderChapters {
    static func markers(starts: [Int], titles: [Int: String]) -> [ChapterMarker] {
        starts.sorted().map { ChapterMarker(index: $0, title: titles[$0]) }
    }

    /// The nearest chapter start before `index`, or `nil` at or before the first.
    static func previousStart(from index: Int, markers: [ChapterMarker]) -> Int? {
        markers.map(\.index).filter { $0 < index }.max()
    }

    /// The nearest chapter start after `index`, or `nil` at or after the last.
    static func nextStart(from index: Int, markers: [ChapterMarker]) -> Int? {
        markers.map(\.index).filter { $0 > index }.min()
    }

    /// The chapter in force at `index`, or `nil` with no markers or before the first.
    static func label(at index: Int, markers: [ChapterMarker]) -> ChapterLabel? {
        let sorted = markers.sorted { $0.index < $1.index }
        guard let position = sorted.lastIndex(where: { $0.index <= index }) else { return nil }
        if let title = sorted[position].title, !title.isEmpty { return .named(title) }
        return .position(position + 1)
    }

    /// The badge on a chapter's first page: the issue number its title gives, else its
    /// position among the chapters. `nil` on a page that starts no chapter.
    static func badge(at index: Int, markers: [ChapterMarker]) -> String? {
        let sorted = markers.sorted { $0.index < $1.index }
        guard let position = sorted.firstIndex(where: { $0.index == index }) else { return nil }
        if let number = sorted[position].title.flatMap(issueNumber(in:)) { return "#\(number)" }
        return "#\(position + 1)"
    }

    /// The whole title when it is only digits, or a trailing "#4".
    static func issueNumber(in title: String) -> String? {
        if !title.isEmpty, title.allSatisfy(\.isNumber) { return title }
        guard let range = title.range(of: #"#\s*\d+\s*$"#, options: .regularExpression) else { return nil }
        return title[range].filter(\.isNumber)
    }

    /// Where each chapter start falls along the slider, as a fraction of its track.
    static func tickFractions(markers: [ChapterMarker], pageCount: Int) -> [Double] {
        guard pageCount > 1 else { return [] }
        return markers.map { Double($0.index) / Double(pageCount - 1) }
    }
}

/// Where a turn past the last page goes: the end of the publication.
///
/// `comic-reader`, *Reaching the end*, with `desktop-experience`, *A key at the end*: the
/// page does not move, an end screen offers the next publication without opening it, and
/// nothing is announced as an error.
enum ReaderEnd {
    static func isPastEnd(slot: Int, step: Int, slotCount: Int) -> Bool {
        step > 0 && slotCount > 0 && slot + step >= slotCount
    }
}
