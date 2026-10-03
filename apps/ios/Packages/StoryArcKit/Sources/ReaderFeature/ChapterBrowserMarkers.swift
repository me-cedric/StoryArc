internal import Formats

/// A chapter's start, for the page browser carousel and the page slider's ticks.
///
/// `page-browser-carousel`: the carousel names "the centred page's chapter" and marks
/// "the first page of each chapter" with a badge; the slider marks "a tick at the start
/// of each chapter". One marker answers both: where the chapter starts, and what to
/// call it.
struct ChapterMarker: Equatable, Sendable {
    let index: Int
    /// The marker's own name, when it carries one. `nil` falls back to "Chapter %d".
    let title: String?
}

/// What the carousel says above itself, free of the localized string it becomes.
///
/// A marker's title names the chapter; without one, the name is the chapter's position
/// among the chapters. Carrying only the position (not the finished "Chapter %d") is
/// what lets a test check the number without building a `Text`.
enum ChapterLabel: Equatable {
    case named(String)
    case position(Int)
}

/// The rules the carousel and the slider share, free of any view so a test can reach
/// them without building one.
enum ChapterBrowser {
    /// Markers built from a comic archive's declared chapter starts and their titles.
    ///
    /// `ComicArchiveReading.chapterStartIndices` is already filtered to pages the
    /// archive actually has (`PageDeclarations.chapterStarts`); a title missing from
    /// `titles` is a start with a blank or absent `Bookmark` text.
    static func markers(comicStarts: [Int], titles: [Int: String]) -> [ChapterMarker] {
        comicStarts.sorted().map { ChapterMarker(index: $0, title: titles[$0]) }
    }

    /// Markers built from a PDF's own outline, one per page an entry resolves to.
    ///
    /// `PdfOutlineChapters.startIndices` already flattens and sorts the tree; this
    /// keeps the title that goes with each start, which that function discards because
    /// the chapter actions it serves only need the page.
    static func markers(pdfOutline items: [PdfOutlineItem]) -> [ChapterMarker] {
        var titles: [Int: String] = [:]
        func visit(_ items: [PdfOutlineItem]) {
            for item in items {
                if let index = item.pageIndex, titles[index] == nil {
                    titles[index] = item.title
                }
                visit(item.children)
            }
        }
        visit(items)
        return titles.keys.sorted().map { ChapterMarker(index: $0, title: titles[$0]) }
    }

    /// The marker in force at `index`: the last one whose start is at or before it.
    ///
    /// `nil` before the first chapter starts — a publication need not open on one.
    static func activeMarker(at index: Int, markers: [ChapterMarker]) -> ChapterMarker? {
        markers.filter { $0.index <= index }.max { $0.index < $1.index }
    }

    /// What the carousel names above itself for the page at `index`.
    ///
    /// `nil` with no markers at all — the "No chapter markers" scenario draws nothing —
    /// and before the first chapter starts, which a publication need not open on.
    static func chapterLabel(at index: Int, markers: [ChapterMarker]) -> ChapterLabel? {
        guard !markers.isEmpty, let marker = activeMarker(at: index, markers: markers) else {
            return nil
        }
        if let title = marker.title, !title.isEmpty { return .named(title) }
        let sorted = markers.sorted { $0.index < $1.index }
        let position = (sorted.firstIndex { $0.index == marker.index } ?? 0) + 1
        return .position(position)
    }

    /// The badge text for a chapter's first page, or `nil` when `index` does not start one.
    ///
    /// design.md §5: "the issue number the marker gives … without a number, the
    /// chapter's position." A marker's title is read as a number when it is nothing but
    /// digits — the one shape a free-text `Bookmark` or outline title can give
    /// unambiguously.
    static func badgeText(at index: Int, markers: [ChapterMarker]) -> String? {
        let sorted = markers.sorted { $0.index < $1.index }
        guard let position = sorted.firstIndex(where: { $0.index == index }) else { return nil }
        let marker = sorted[position]
        if let title = marker.title, !title.isEmpty, title.allSatisfy(\.isNumber) {
            return "#\(title)"
        }
        return "#\(position + 1)"
    }

    /// Where each chapter start falls along the slider, as a fraction of its track.
    ///
    /// Empty with one page or none: there is no track to place a fraction on.
    static func tickFractions(markers: [ChapterMarker], pageCount: Int) -> [Double] {
        guard pageCount > 1 else { return [] }
        return markers.map { Double($0.index) / Double(pageCount - 1) }
    }

    /// Where a tick at `fraction` goes along the slider, in points from its leading end.
    ///
    /// The thumb never reaches past the track, so its centre runs from half the thumb's
    /// width to the track's width less half the thumb's width. A tick sits where the
    /// thumb's centre sits on that chapter's first page, not at `fraction` of the track.
    static func tickOffset(fraction: Double, trackWidth: Double, thumbWidth: Double) -> Double {
        let inset = min(thumbWidth, trackWidth) / 2
        return inset + fraction * (trackWidth - inset * 2)
    }
}
