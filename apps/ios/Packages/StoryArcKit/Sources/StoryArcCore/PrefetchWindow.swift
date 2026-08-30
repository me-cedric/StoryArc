public import Foundation

/// How hard the system is asking for memory back.
///
/// Three states rather than a number, because the two platforms report this in
/// different units — Darwin's dispatch source has exactly these three levels, and
/// Android's `onTrimMemory` has seven that collapse onto them. Naming the *state* is
/// what keeps the two readers behaving the same way under the same conditions.
public enum MemoryPressure: String, Sendable, Equatable, CaseIterable {
    /// Nothing is wrong; keep the full window.
    case normal
    /// The system would like memory back.
    case warning
    /// The system is about to start killing processes.
    case critical
}

/// How many pages either side of the current one the reader keeps decoded.
///
/// `comic-reader` asks for two things that pull against each other: "at least the next
/// three and previous one page are decoded and held ready", and "prefetch depth shrinks
/// under memory pressure rather than the app being terminated". The second wins when it
/// applies — a reader that was killed for holding five pages has held nothing at all —
/// and the first is what the window returns to as soon as the pressure lifts.
///
/// A page of a 2000×3000 scan is about 24 MB decoded, so the difference between the full
/// window and the critical one is roughly a hundred megabytes. That is the size of the
/// decision being made here.
///
/// Android's `PrefetchWindow` is the same table.
public struct PrefetchWindow: Sendable, Equatable {
    /// Pages after the current one.
    public let ahead: Int
    /// Pages before it.
    public let behind: Int
    /// How many times the display's own resolution a held zoom may re-decode a page at.
    ///
    /// `publication-formats` asks for a page too large for the device to be "downsampled
    /// to the display's needs for viewing and re-decoded at higher resolution when the
    /// user zooms". The second half of that sentence costs memory, which is why it is a
    /// property of this window rather than of the zoom gesture: the same rule that
    /// narrows the prefetch under pressure is the rule that decides how much sharper a
    /// magnified page is allowed to get. `1` means no re-decode at all.
    public let zoomCeiling: Int

    public init(ahead: Int, behind: Int, zoomCeiling: Int = 3) {
        self.ahead = ahead
        self.behind = behind
        self.zoomCeiling = zoomCeiling
    }

    /// How far a page must be magnified before re-decoding it buys anything.
    ///
    /// A quarter more detail. Below that the reader is nudging the pinch rather than
    /// looking closer, and a full decode per nudge is work nobody asked for.
    public static let minimumZoomGain = 1.25

    /// The spec's floor: three ahead covers a fast run of turns, one behind covers the
    /// glance back.
    public static let full = PrefetchWindow(ahead: 3, behind: 1, zoomCeiling: 3)

    /// What to hold under a given pressure.
    ///
    /// Warning keeps one page either side, which is still enough for a turn in either
    /// direction to be instant. Critical keeps only the page on screen: at that point the
    /// system is choosing which process to end, and a reader who waits 200 ms for the
    /// next page has lost far less than one whose app disappeared.
    public static func under(_ pressure: MemoryPressure) -> PrefetchWindow {
        switch pressure {
        case .normal: full
        case .warning: PrefetchWindow(ahead: 1, behind: 1, zoomCeiling: 2)
        case .critical: PrefetchWindow(ahead: 0, behind: 0, zoomCeiling: 1)
        }
    }

    /// The page numbers to hold around a position, clamped to what exists.
    public func pages(around index: Int, of count: Int) -> Set<Int> {
        Set((index - behind)...(index + ahead)).filter { $0 >= 0 && $0 < count }
    }

    /// What to re-decode a magnified page at, or `nil` when there is nothing to gain.
    ///
    /// One page decoded twice is the cost being weighed here, so the answer is `nil`
    /// wherever the second decode would not pay for itself: a pinch too small to see,
    /// a window with no room to spare, and — the case that matters on a phone — a
    /// magnification the ceiling has already reached, where holding the pinch further
    /// asks for pixels the device was told not to spend.
    ///
    /// - Parameters:
    ///   - display: the bound the page is already decoded at, in pixels.
    ///   - scale: how far the reader has magnified it, 1 being fit.
    public func zoomedPixelSize(display: Int, scale: Double) -> Int? {
        guard display > 0, zoomCeiling > 1, scale >= Self.minimumZoomGain else { return nil }
        let wanted = min(Double(display) * scale, Double(display * zoomCeiling))
        let bound = Int(wanted.rounded())
        return bound > display ? bound : nil
    }
}
