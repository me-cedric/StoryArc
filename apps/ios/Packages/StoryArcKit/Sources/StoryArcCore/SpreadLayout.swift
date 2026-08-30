public import Foundation

/// One slot in the reader's page order: a page on its own, or two facing pages.
///
/// `leading` and `trailing` are in the publication's own order, not in screen order.
/// `comic-reader` asks for a pair "side by side in the correct order for the reading
/// direction", and which side each page lands on is the view's business — a manga
/// spread reads 4 then 5 exactly as a western one does, it just puts 4 on the right.
public struct Spread: Sendable, Equatable {
    public let leading: Int
    public let trailing: Int?

    public init(leading: Int, trailing: Int? = nil) {
        self.leading = leading
        self.trailing = trailing
    }

    /// The pages in this slot, in reading order.
    public var pages: [Int] {
        guard let trailing else { return [leading] }
        return [leading, trailing]
    }

    public var isPair: Bool { trailing != nil }
}

/// The reader's page order once two pages may share the screen.
///
/// `comic-reader`: "WHEN two consecutive pages are portrait and the device is in
/// landscape THEN they are shown side by side in the correct order for the reading
/// direction AND a page detected as a single wide spread is shown alone, never split
/// across two turns AND the user can offset the pairing by one page, for publications
/// whose cover throws the pairing off."
///
/// All three rules live here rather than in either reader, because they are arithmetic
/// and arithmetic is the thing that diverges silently between two codebases. The view
/// asks for a layout and then only ever counts *slots*; the model keeps counting pages
/// the way the publication does, so the indicator still says "12 of 220".
///
/// ``single(pageCount:)`` is the portrait case and the continuous-scroll case, and it
/// is deliberately the same type: every screen the reader draws goes through a layout,
/// so there is no second code path that only runs when a device is held one way up.
///
/// Android's `SpreadLayout` is the same type.
public struct SpreadLayout: Sendable, Equatable {
    /// The slots, in the publication's own order.
    public let slots: [Spread]

    /// Which slot each page landed in, by page number.
    ///
    /// Precomputed rather than searched: the reader asks this on every layout pass, for
    /// the slider, the strip and the counter, and a scan of two hundred slots per pass
    /// is work that never had to happen.
    private let slotOfPage: [Int]

    public var count: Int { slots.count }

    /// Every page on its own.
    ///
    /// Portrait, a continuous scroll, and a publication of one page all want this.
    public static func single(pageCount: Int) -> SpreadLayout {
        SpreadLayout(slots: (0..<max(0, pageCount)).map { Spread(leading: $0) })
    }

    /// Facing pages, paired.
    ///
    /// - Parameters:
    ///   - wide: pages that take the width of two — declared by `ComicInfo` or found to
    ///     be landscape when they decoded. Each one stands alone, and so does the page
    ///     that would otherwise have been paired with it: pairing a portrait page with
    ///     the *next* portrait page across a spread would put two unrelated halves of
    ///     the story beside each other.
    ///   - isOffset: whether to shift the pairing by one. A comic whose cover is page
    ///     one pairs 1-2, 3-4 by default, which is off by one for the printed book —
    ///     the reader says so and the cover then stands alone.
    public static func paired(pageCount: Int, wide: Set<Int>, isOffset: Bool) -> SpreadLayout {
        var slots: [Spread] = []
        var index = 0
        if isOffset, pageCount > 0 {
            slots.append(Spread(leading: 0))
            index = 1
        }
        while index < pageCount {
            let alone = wide.contains(index)
                || index + 1 >= pageCount
                || wide.contains(index + 1)
            if alone {
                slots.append(Spread(leading: index))
                index += 1
            } else {
                slots.append(Spread(leading: index, trailing: index + 1))
                index += 2
            }
        }
        return SpreadLayout(slots: slots)
    }

    private init(slots: [Spread]) {
        self.slots = slots
        let pageCount = slots.reduce(0) { $0 + $1.pages.count }
        var lookup = [Int](repeating: 0, count: pageCount)
        for (slot, spread) in slots.enumerated() {
            for page in spread.pages where lookup.indices.contains(page) {
                lookup[page] = slot
            }
        }
        self.slotOfPage = lookup
    }

    /// The slot a page is shown in. Zero for a page that is not in this layout, which
    /// is the same answer the reader gives for any index it cannot place.
    public func slot(containing page: Int) -> Int {
        slotOfPage.indices.contains(page) ? slotOfPage[page] : 0
    }

    public subscript(slot: Int) -> Spread? {
        slots.indices.contains(slot) ? slots[slot] : nil
    }

    /// Whether anything here is actually a pair.
    ///
    /// What decides whether the reader offers the offset control at all: a publication
    /// of nothing but wide pages has a layout with no pairing to shift.
    public var hasPairs: Bool { slots.contains { $0.isPair } }
}
