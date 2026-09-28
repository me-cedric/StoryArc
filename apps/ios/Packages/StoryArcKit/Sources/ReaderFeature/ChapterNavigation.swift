/// Where the previous or next chapter action goes: within this publication first, and
/// only past its first or last chapter to a neighbouring publication.
///
/// Decision D4: chapter markers are `ComicInfo`'s `Bookmark` pages, and — on iOS —
/// a PDF's own outline, wherever the platform exposes one. A struct of its own, so
/// `ChapterNavigationTests` can drive it with plain numbers — the same reason
/// `EarlyPageTallness` is split out. Android's `ChapterNavigation` asserts the same
/// table.
enum ChapterNavigation {
    /// The nearest chapter start before `index`, or `nil` at or before the first —
    /// which is when the previous-chapter action opens a neighbouring publication.
    static func previousStart(from index: Int, starts: [Int]) -> Int? {
        starts.filter { $0 < index }.max()
    }

    /// The nearest chapter start after `index`, or `nil` at or after the last —
    /// which is when the next-chapter action opens a neighbouring publication.
    static func nextStart(from index: Int, starts: [Int]) -> Int? {
        starts.filter { $0 > index }.min()
    }
}
