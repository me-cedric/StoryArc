internal import Foundation

internal import Persistence
internal import StoryArcCore

/// A page bookmark for a fixed-page publication, stored as an `Annotation` — the same
/// record and the same store PDF marks use (D8). A comic and a scanned PDF have no
/// words to select, so the "highlight" this store otherwise holds is a plain page
/// mark instead: `text` names the page rather than quoting it.
///
/// A locator of its own rather than `PdfLocator`'s: the two never meet in one
/// publication's list (a file is one format or the other), and a page index needs
/// none of a text selection's rectangles.
enum ComicPageBookmark {
    /// The `Annotation` a bookmark of `index` becomes.
    ///
    /// `@MainActor`: it reuses `PdfTextModel.chapter(ofPage:)`, which is — the other
    /// functions here are plain arithmetic and stay off it, so a test can call them
    /// without one.
    @MainActor
    static func annotation(forPage index: Int, of pageCount: Int, createdAt: Date) -> Annotation {
        Annotation(
            locator: String(index),
            resource: String(index),
            progression: progression(forPage: index, of: pageCount),
            chapter: "",
            // Reuses `PdfTextModel`'s own "Page N" — a mark here has no selected words
            // to be the main line, so the page number takes that place instead of the
            // caption above it.
            text: PdfTextModel.chapter(ofPage: index),
            createdAt: createdAt
        )
    }

    /// How far through the publication `index` falls, for ``Array/inReadingOrder``.
    static func progression(forPage index: Int, of pageCount: Int) -> Double {
        guard pageCount > 1 else { return 0 }
        return min(1, max(0, Double(index) / Double(pageCount - 1)))
    }

    /// The page a bookmark's own locator names, or `nil` for one this format did not write.
    static func pageIndex(of annotation: Annotation) -> Int? {
        Int(annotation.locator)
    }

    /// Whether `pageIndex` already carries one of `annotations`.
    static func isBookmarked(_ pageIndex: Int, among annotations: [Annotation]) -> Bool {
        annotations.contains { self.pageIndex(of: $0) == pageIndex }
    }

    /// Bookmarks `pageIndex`, unless it already carries one — a reader who presses the
    /// row twice on the same page gets one bookmark, not two.
    @MainActor
    static func add(_ pageIndex: Int, of pageCount: Int, to store: AnnotationStore?, for publication: String) {
        guard let store, pageCount > 0 else { return }
        guard !isBookmarked(pageIndex, among: store.annotations(for: publication)) else { return }
        store.save(annotation(forPage: pageIndex, of: pageCount, createdAt: Date()), in: publication)
    }
}
