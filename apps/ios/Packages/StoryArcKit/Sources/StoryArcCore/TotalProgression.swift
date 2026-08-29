public import Foundation

/// How far through a whole publication a position is.
///
/// A rule rather than a rendering detail, which is why it lives here and not in either
/// reader: both need it, and a renderer that reports one thing on one platform and
/// another on the other is exactly the divergence this file exists to prevent.
public enum TotalProgression {
    /// Resolves the renderer's own answer against where it says the reader is.
    ///
    /// Readium fills in a total progression only once it has computed a positions list,
    /// which it does lazily and not at all for some publications. Without a fallback the
    /// reader sits at "0% read" for a whole book, which is worse than an approximation —
    /// so the fallback places the current resource in the reading order and adds how far
    /// through that resource the reader is.
    ///
    /// The subtlety, and the reason this is a function rather than a `??`: **a reported
    /// zero is not the same as no report.** In scroll mode Readium answers `0.0` rather
    /// than nothing, so `reported ?? fallback` takes the zero and the reader watches
    /// "0% read" while scrolling through chapter one. A reported zero that contradicts
    /// where the renderer says the reader is, is not a report.
    ///
    /// - Parameters:
    ///   - reported: what the renderer said, if it said anything.
    ///   - within: how far through the current resource, 0…1.
    ///   - resourceIndex: where that resource sits in the reading order, or a negative
    ///     number if it could not be found.
    ///   - resourceCount: how many resources the reading order has.
    public static func resolve(
        reported: Double?,
        within: Double,
        resourceIndex: Int,
        resourceCount: Int
    ) -> Double {
        let estimate = estimated(
            within: within, resourceIndex: resourceIndex, resourceCount: resourceCount
        )
        guard let reported else { return estimate ?? 0 }
        // Trust the report unless it is a zero the position contradicts.
        if reported == 0, let estimate, estimate > 0 { return estimate }
        return min(max(reported, 0), 1)
    }

    /// Where one resource sits in the reading order, or `-1` when it is not in it.
    ///
    /// Here rather than at the call site, and comparing on more than equality, because a
    /// locator's href is not always spelled the way the reading order spells it. A locator
    /// that came from a link carries the fragment the link pointed at, and one that came
    /// from a search can carry a query; neither is part of the resource's identity, and
    /// neither matched, so the resource could not be placed and the reader watched one
    /// percentage for a whole chapter.
    public static func index(of href: String, in readingOrder: [String]) -> Int {
        let wanted = withoutFragment(href)
        return readingOrder.firstIndex { withoutFragment($0) == wanted } ?? -1
    }

    private static func withoutFragment(_ href: String) -> String {
        String(href.prefix { $0 != "#" && $0 != "?" })
    }

    /// Where the reader is, from the reading order alone. `nil` when it cannot be told.
    private static func estimated(
        within: Double,
        resourceIndex: Int,
        resourceCount: Int
    ) -> Double? {
        guard resourceCount > 0, resourceIndex >= 0 else { return nil }
        let clamped = min(max(within, 0), 1)
        return min(max((Double(resourceIndex) + clamped) / Double(resourceCount), 0), 1)
    }
}
