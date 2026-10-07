internal import CoreGraphics

internal import StoryArcCore

/// Where a page stands mid-turn, and what a finger does to it from there.
///
/// Pulled out of the gesture so it can be tested without a touch screen, the way
/// `SpreadLayout` and `PrefetchWindow` are: this is the whole rule, and the rest of
/// ``CurledPages`` is SwiftUI's gesture plumbing. Android's `CurlTurn` is its twin.
///
/// In a file of its own because `CurledPages.swift` reached the 400-line cap this project
/// enforces when the curl learned to answer a tap (``CurlRequest``). The arithmetic is the
/// half of that file nothing on screen depends on, so it is the half that moved.
enum CurlTurn {

    /// Travel in turn-space: positive is towards a completed turn.
    ///
    /// A right-to-left publication turns forward when the finger moves the other way, so
    /// one sign carries the whole mirroring.
    static func forward(travel: Double, isRightToLeft: Bool) -> Double {
        isRightToLeft ? travel : -travel
    }

    /// Where the page stands after `travel` points of drag from `base`.
    ///
    /// The base is the whole point. `comic-reader` requires a drag begun during a settle
    /// to take over "from the current position without the page snapping", so the drag is
    /// an *offset* from where the page stands rather than an absolute reading of the
    /// finger: a settle caught at 0.8 and nudged one point stays at 0.8, where reading the
    /// finger alone would have put it at 0.001.
    ///
    /// It is also what lets a caught settle be pushed back. Clamping an absolute reading
    /// at zero made every backwards move mean "no progress"; clamping base plus travel
    /// makes it mean "less progress", which is the same gesture read correctly.
    ///
    /// - Parameters:
    ///   - base: the page's progress when the finger took it over, 0 for a flat page.
    ///   - travel: raw horizontal points since the drag was recognised.
    ///   - width: what a whole turn is measured against. A width nothing has measured yet
    ///     leaves the page where it stands rather than dividing by it.
    ///   - canTurnBack: false at the first page, where a backwards drag moves nothing.
    ///   - canTurnForward: false where ``under(beneath:endsHere:)`` answers `.nothing`.
    ///     D10: the last page of a publication lifts off its end screen, which is the next
    ///     sheet, and nothing lifts where there is no sheet of any kind beneath.
    static func progress(
        base: Double,
        travel: Double,
        width: Double,
        isRightToLeft: Bool,
        canTurnBack: Bool = true,
        canTurnForward: Bool = true
    ) -> Double {
        let floor: Double = canTurnBack ? -1 : 0
        let ceiling: Double = canTurnForward ? 1 : 0
        guard width > 0 else { return min(max(base, floor), ceiling) }
        let offset = forward(travel: travel, isRightToLeft: isRightToLeft) / width
        return min(max(base + offset, floor), ceiling)
    }

    /// Whether the finger left fast, in the direction the page is already going.
    ///
    /// Signed, and it has to be: a fast finger dragging a half-turned page *back* has said
    /// it does not want the turn, and a fast finger dragging the page behind into view has
    /// asked for that one. An unsigned flick answered both with "complete the forward
    /// turn".
    ///
    /// - Parameter velocity: the finger's predicted travel in turn-space, positive
    ///   towards a completed forward turn. SwiftUI's own flick model supplies it.
    static func flicks(velocity: Double, progress: Double) -> Bool {
        progress < 0 ? velocity < -flickPoints : velocity > flickPoints
    }

    /// Which sheet the shader turns, which page lies under it, and at what forward
    /// progress.
    ///
    /// **A backwards turn is the forward projection, run on the page behind.** At a whole
    /// turn back the previous page lies flat and fully in view, which is the forward
    /// projection at rest; at nothing dragged it is folded entirely away and the current
    /// page is what shows, which is the forward projection completed. So `1 + progress`
    /// carries the whole of it, and the shader needs no second direction.
    ///
    /// Generic over the image type so the mapping can be asserted without a bitmap.
    static func sheets<T>(
        progress: Double,
        page: T?,
        beneath: T?,
        previous: T?
    ) -> Sheets<T> {
        progress < 0
            ? Sheets(turning: previous, under: page, progress: 1 + progress)
            : Sheets(turning: page, under: beneath, progress: progress)
    }

    /// What ``sheets(progress:page:beneath:previous:)`` decided.
    struct Sheets<T> {
        let turning: T?
        let under: T?
        let progress: Double
    }

    /// How far a finger has to be predicted to travel for the turn to complete anyway.
    ///
    /// `predictedEndTranslation` is SwiftUI's own flick model, so this is a threshold on
    /// its answer rather than a velocity calculation of ours.
    static let flickPoints: Double = 40

    /// Whether a released turn completes rather than springing back.
    ///
    /// Past halfway it completes; before it, it springs back. A flick completes whatever
    /// the distance, because a fast finger has already said what it meant — and a page
    /// that never left flat is not a turn at all, however fast the finger left it.
    static func settles(progress: Double, isFlick: Bool) -> Bool {
        abs(progress) > 0.5 || (isFlick && abs(progress) > 0.05)
    }

    /// The travel a finger's velocity predicts, in points, for ``flicks(velocity:progress:)``.
    ///
    /// The page's own pan recogniser reports a velocity in points per second, not
    /// SwiftUI's predicted end. A twentieth of a second of it puts the flick at 800 points
    /// per second, which is the number Android's `CurlTurn.flicks` thresholds in dp.
    static func predictedTravel(velocity: Double) -> Double {
        velocity * flickSeconds
    }

    /// See ``predictedTravel(velocity:)``.
    static let flickSeconds: Double = 0.05

    /// What a forward turn lifts the page off.
    enum Under: Equatable {
        /// The next sheet of the publication, or its placeholder.
        case sheet
        /// The end-of-publication screen. D10: past the last page the end screen is the
        /// next sheet, so the page lifts off it rather than off nothing.
        case endScreen
        /// Nothing, so nothing lifts.
        case nothing
    }

    /// What lies under a forward turn of this page.
    ///
    /// - Parameter endsHere: true when no slot follows this one in reading order, so the
    ///   publication's end screen comes next.
    static func under<T>(beneath: T?, endsHere: Bool) -> Under {
        if beneath != nil { return .sheet }
        return endsHere ? .endScreen : .nothing
    }

    /// The outline of the turning sheet: every point with x at or before the lip's rim.
    ///
    /// Past the rim the shader draws the page beneath. When that is the end screen, the
    /// shader leaves it transparent and the matte has to stop at the same curve, or the end
    /// screen shows through only where the matte was not. `PageRoll` is the one model both
    /// use, so the curve is the shader's own.
    ///
    /// - Parameter steps: how many segments approximate the rim from top to foot.
    static func sheetOutline(
        width: Double,
        height: Double,
        progress: Double,
        isRightToLeft: Bool,
        steps: Int = 24
    ) -> [CGPoint] {
        let radius = PageRoll.radius(width: width, progress: progress)
        let count = max(steps, 1)
        let rim = (0...count).map { step -> CGPoint in
            let y = height * Double(step) / Double(count)
            let fold = PageRoll.fold(width: width, height: height, progress: progress, y: y, radius: radius)
            let x = min(max(fold + radius, 0), width)
            return CGPoint(x: isRightToLeft ? width - x : x, y: y)
        }
        let spine: Double = isRightToLeft ? width : 0
        return [CGPoint(x: spine, y: 0)] + rim + [CGPoint(x: spine, y: height)]
    }
}
