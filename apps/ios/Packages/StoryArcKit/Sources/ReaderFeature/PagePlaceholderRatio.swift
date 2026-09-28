/// The placeholder ratio for a page not yet decoded, and where it comes from.
///
/// `page-transitions` asks for the placeholder to hold "the correct aspect ratio, so the
/// turn does not jump when the content arrives" — a fixed 2:3 does that for an ordinary
/// comic page and badly for a webtoon, whose pages are many times taller than wide.
///
/// **Not a page header read.** A page far enough ahead to still show a placeholder has
/// not been fetched yet either, on a slow source, so there are no bytes to read a
/// header from — the gap this was built against is exactly a webtoon scroll from one.
/// The nearest page that *has* decoded is the best guess this app can make without it.
enum PagePlaceholder {
    /// A comic page's own proportions, before anything is known about a webtoon.
    static let defaultRatio = 2.0 / 3.0

    /// The ratio of whichever decoded page is closest to `index`, or ``defaultRatio``
    /// when nothing has decoded yet. A struct of its own, so `PagePlaceholderTests` can
    /// drive it with plain numbers — the same reason `EarlyPageTallness` is split out.
    ///
    /// Broken by the lower index on an exact tie — `Dictionary`'s own order is not
    /// stable across launches, and a placeholder that could pick either neighbour
    /// depending on a hash seed is not one a test can hold to a single answer.
    static func ratio(nearest index: Int, among ratios: [Int: Double]) -> Double {
        guard let nearest = ratios.keys.min(by: { (abs($0 - index), $0) < (abs($1 - index), $1) })
        else { return defaultRatio }
        return ratios[nearest] ?? defaultRatio
    }
}
