internal import Foundation

/// Where a rolling page's surface is, and how the light falls on it.
///
/// **The projection, in arithmetic, so it can be asserted.** `PageCurl.metal` and Android's
/// AGSL are transliterations of what is here, and ``PageRollTests`` and Android's
/// `PageRollTest` assert this against the same table of expected values — which is how
/// `design.md`'s "one projection expressed twice rather than solved twice" is held to when
/// no test process has a GPU in it. The constants reach the shader as parameters read from
/// here, so a number cannot drift; only the formula can, and `PageCurlShaderTests` is the
/// guard on that.
///
/// **The model.** The sheet lies flat to the fold, wraps a cylinder of radius
/// ``radius(width:progress:)`` whose lower tangent is the fold, and comes back over itself
/// lying flat. So the lip bulges to the *right* of the fold, over the page beneath, and the
/// flat back face runs leftwards from it — which is where a real page's thickness shows,
/// and what ADR-0009's crease of no radius could not draw. Four regions across the width,
/// at each height: the page's own front face out to the sheet's free edge; the flat back
/// face from that edge to the fold; the lip, from the fold to the rim a radius further
/// right; and the page beneath, with the lip's shadow cast on it.
///
/// **The fold leans**, by ``lean`` radii over the height, so the bottom corner runs ahead
/// of the top one. Without it every edge in the picture is a vertical line, which is the
/// difference between a page turning and a wipe.
///
/// At a progress of 0 and 1 the radius is zero, every region collapses to the fold this
/// replaces, and the ends of a turn are pixel-for-pixel what they were.
enum PageRoll {

    /// The lip's radius at its widest, as a fraction of the page's width.
    static let radiusMax: Double = 0.04

    /// How far the fold leans over the page's height, in radii.
    static let lean: Double = 1.5

    /// How much of the lip's brightness survives at the rim, where it is edge-on.
    static let rim: Double = 0.35

    /// Which surface a point on the screen shows.
    enum Region { case front, back, lip, under }

    /// What to draw at one point.
    struct Sample {
        /// Where on the page the surface at this point came from, in turn-space x.
        /// Meaningless for ``Region/under``, which samples the page beneath at the screen
        /// point itself.
        let region: Region
        let material: Double
        /// What to multiply the sampled colour by.
        let shade: Double
        /// What to add afterwards, which is the sheen along the top of the lip.
        let lit: Double
    }

    /// The lip's radius at this progress.
    ///
    /// A sine, so the roll grows from nothing, is at its fullest halfway through the turn,
    /// and is back to nothing when the page lands. Floored at zero because `sin` of a
    /// float pi is a hair below it, and a negative radius puts the rim to the left of the
    /// fold — which drew the page beneath across a page that had just landed.
    static func radius(width: Double, progress: Double) -> Double {
        max(radiusMax * width * sin(.pi * min(max(progress, 0), 1)), 0)
    }

    /// Where the sheet leaves the page at this height.
    static func fold(width: Double, height: Double, progress: Double, y: Double, radius: Double) -> Double {
        let flat = width * (1 - min(max(progress, 0), 1))
        guard height > 0 else { return flat }
        return flat + lean * radius * (0.5 - y / height)
    }

    // swiftlint:disable function_parameter_count

    /// What the screen shows at (`x`, `y`).
    ///
    /// The eight parameters are the shader's own, in the shader's own order, because this
    /// function is what the shader is a transliteration of — grouping them into a struct
    /// here would make the two harder to read against each other, which is the one thing
    /// ``PageCurlShaderTests`` exists to keep possible.
    ///
    /// - Parameters:
    ///   - crease: how far the sheen reaches from the fold, as a fraction of the width.
    ///   - shadow: how far the lip's shadow reaches, as a fraction of the width.
    ///   - back: how much light the flat back face keeps.
    static func sample(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        progress: Double,
        crease: Double,
        shadow: Double,
        back: Double
    ) -> Sample {
        let radius = radius(width: width, progress: progress)
        let fold = fold(width: width, height: height, progress: progress, y: y, radius: radius)
        let lipRim = fold + radius
        let sheen = { (away: Double) -> Double in
            let reach = away / (width * crease)
            return exp(-reach * reach) * 0.5
        }

        if x > lipRim {
            let beyond = (x - lipRim) / (width * shadow)
            return Sample(region: .under, material: x, shade: 1 - 0.45 * exp(-beyond * beyond), lit: 0)
        }

        if radius > 0, x >= fold {
            // The visible half of the cylinder is the upper one, so the angle runs back
            // from a half turn at the fold to a quarter turn at the rim. Arc length is what
            // the sheet spends getting there, and arc length is where the texture came
            // from — which is the whole of the remapping the fold had none of.
            let across = min(max((x - fold) / radius, 0), 1)
            let angle = Double.pi - asin(across)
            let lambert = -cos(angle)
            return Sample(
                region: .lip,
                material: fold + radius * angle,
                shade: back * (rim + (1 - rim) * lambert),
                lit: sheen(x - fold)
            )
        }

        // The flat back face, shifted by the half circumference the lip spent bending.
        let edge = 2 * fold - width + .pi * radius
        if x < edge { return Sample(region: .front, material: x, shade: 1, lit: 0) }
        return Sample(
            region: .back,
            material: 2 * fold - x + .pi * radius,
            shade: back,
            lit: sheen(fold - x)
        )
    }

    // swiftlint:enable function_parameter_count
}
