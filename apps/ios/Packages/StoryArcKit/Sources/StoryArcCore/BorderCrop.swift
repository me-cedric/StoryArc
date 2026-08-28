/// Finds the uniform margin around a scanned page.
///
/// `comic-reader`: "uniform white or black margins are detected and trimmed per page". A
/// scan taken on a flatbed carries the lid; a scan taken from print carries the paper. Both
/// are a band of one colour around the artwork, and both cost a reader a third of the screen.
///
/// The rule is deliberately timid. A row is margin only if every sample in it is within
/// ``tolerance`` of the corner it started from *and* that corner is itself near-white or
/// near-black. Artwork that happens to start with a pale sky is not a margin, and a page
/// cropped into is worse than a page not cropped at all.
public enum BorderCrop {
    /// How far two samples may differ and still count as the same colour, out of 255.
    ///
    /// Twelve, because a JPEG's flat white is not flat: the block edges of a scanned margin
    /// measured eight or nine apart on the fixture scans, and a threshold below that found
    /// no margin at all.
    public static let tolerance = 12

    /// How much of a page may be taken. Beyond this the detection is wrong about something.
    ///
    /// A page that is nine tenths margin is a page whose artwork the sampler missed, and
    /// handing the reader a sliver is the one outcome worse than handing them the margin.
    public static let limit = 0.4

    /// How far the first line of artwork must sit from the margin for the margin to be one.
    ///
    /// A margin ends at an edge. Without this a smooth gradient reads as a deep margin --
    /// every one of its rows is uniform along its own length -- and the top of the artwork
    /// is quietly cut off. Three times the tolerance, because anything a reader would call
    /// an edge clears it easily and nothing continuous does.
    public static let edge = tolerance * 3

    /// One page's edges, as the number of pixels to trim from each.
    public struct Inset: Sendable, Equatable {
        public var top: Int
        public var left: Int
        public var bottom: Int
        public var right: Int

        public init(top: Int = 0, left: Int = 0, bottom: Int = 0, right: Int = 0) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }

        /// Nothing to trim.
        public static let none = Inset()

        public var isEmpty: Bool { self == .none }
    }

    /// Reads a single channel's brightness at a point, 0…255.
    ///
    /// A closure rather than a buffer so the rule can be tested against a drawing rather
    /// than against a decoded file, and so each platform keeps its own pixel access.
    public typealias Sample = (_ x: Int, _ y: Int) -> Int

    /// What to trim from a page of this size.
    public static func inset(
        width: Int,
        height: Int,
        sample: Sample
    ) -> Inset {
        guard width > 2, height > 2 else { return .none }
        let cap = (x: Int(Double(width) * limit), y: Int(Double(height) * limit))

        // Probed down the middle, not down the corner: a corner stays margin all the way
        // through the page, so a run measured there never meets the edge that ends it.
        let middle = (x: width / 2, y: height / 2)
        return Inset(
            top: run(
                upTo: cap.y,
                at: { sample(middle.x, $0) },
                isMargin: { uniform(row: $0, width: width, sample: sample) }
            ),
            left: run(
                upTo: cap.x,
                at: { sample($0, middle.y) },
                isMargin: { uniform(column: $0, height: height, sample: sample) }
            ),
            bottom: run(
                upTo: cap.y,
                at: { sample(middle.x, height - 1 - $0) },
                isMargin: { uniform(row: height - 1 - $0, width: width, sample: sample) }
            ),
            right: run(
                upTo: cap.x,
                at: { sample(width - 1 - $0, middle.y) },
                isMargin: { uniform(column: width - 1 - $0, height: height, sample: sample) }
            )
        )
    }

    /// How many lines in from an edge are margin, and zero unless they end at one.
    private static func run(
        upTo cap: Int,
        at value: (Int) -> Int,
        isMargin: (Int) -> Bool
    ) -> Int {
        let reference = value(0)
        var count = 0
        // Each line must look like the first one, not merely like the line before it:
        // a gradient satisfies the second and none of it is a margin.
        while count < cap, isMargin(count), abs(value(count) - reference) <= tolerance {
            count += 1
        }
        guard count > 0, abs(value(count) - reference) >= edge else { return 0 }
        return count
    }

    /// Whether a whole row is one near-white or near-black colour.
    private static func uniform(row: Int, width: Int, sample: Sample) -> Bool {
        let first = sample(0, row)
        guard isPaperOrInk(first) else { return false }
        // Sampled rather than read whole: a margin is uniform by definition, and reading
        // every pixel of every edge of every page is the difference between a page turn
        // that feels immediate and one that does not.
        return stride(from: 0, to: width, by: max(1, width / 64)).allSatisfy {
            abs(sample($0, row) - first) <= tolerance
        }
    }

    private static func uniform(column: Int, height: Int, sample: Sample) -> Bool {
        let first = sample(column, 0)
        guard isPaperOrInk(first) else { return false }
        return stride(from: 0, to: height, by: max(1, height / 64)).allSatisfy {
            abs(sample(column, $0) - first) <= tolerance
        }
    }

    /// Whether a value is close enough to white or to black to be a margin at all.
    ///
    /// `comic-reader` says "white or black margins", and it means it: a flat mid-grey band
    /// is as likely to be artwork as it is to be a border.
    private static func isPaperOrInk(_ value: Int) -> Bool { value >= 226 || value <= 30 }
}
