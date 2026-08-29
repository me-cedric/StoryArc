public import CoreGraphics
public import Foundation

/// The colour a publication's own artwork brings to its own screens.
///
/// `native-experience`: "accent and background tinting derive from the publication's
/// cover art", and "the derived colour is adjusted until it meets the contrast floor
/// in the design tokens, rather than being used raw". Both halves live here, because
/// a raw extracted colour that reaches a view is already a bug — the adjustment is
/// not a refinement a caller may skip.
///
/// Deliberately a mirror of Android's `CoverAccent`, case for case, for the reason
/// `PageOrdering` is: two extractors that disagree give the same book two different
/// colours on the two platforms, and nothing in either test suite would notice.
public enum CoverAccent {
    /// The floor an accent has to clear against what sits behind it.
    ///
    /// 3:1, which is what `docs/design.md` §10 requires of "tertiary and accents" and
    /// what `pnpm tokens:check` holds the shipped palette to. Text on the accent is a
    /// different question, answered by ``ReadingContrast/bestForeground(on:)``.
    public static let floor = 3.0

    /// How far down a cover is sampled before it is counted.
    ///
    /// A colour census, not a picture: 32×32 is a thousand pixels, enough that a
    /// small logo cannot outvote the sky behind it, and cheap enough to do on the
    /// thread that just decoded the page.
    public static let sampleEdge = 32

    /// The dominant colour of a sampled cover, as `#rrggbb`, or `nil` when it has none.
    ///
    /// `nil` is a real answer and the commonest one for manga: a black-and-white
    /// cover has no accent to derive, and inventing one from its greys would tint
    /// every such book the same muddy sepia. The caller falls back to the brand
    /// accent, which is what `native-experience` asks for on a surface with no
    /// publication colour of its own.
    ///
    /// - Parameter pixels: packed `0xRRGGBB` — the low 24 bits are read and anything
    ///   above them ignored, so an `ARGB` word from either platform arrives correct.
    public static func dominant(of pixels: [UInt32]) -> String? {
        var counts: [Int: Int] = [:]
        var sums: [Int: [Int]] = [:]
        for pixel in pixels {
            let red = Int((pixel >> 16) & 0xFF)
            let green = Int((pixel >> 8) & 0xFF)
            let blue = Int(pixel & 0xFF)
            guard carriesColour(red, green, blue) else { continue }
            // Three bits a channel: 512 buckets, which separates a red cape from an
            // orange sky without splitting one sky across four of them.
            let key = (red >> 5) << 6 | (green >> 5) << 3 | (blue >> 5)
            counts[key, default: 0] += 1
            var running = sums[key] ?? [0, 0, 0]
            running[0] += red
            running[1] += green
            running[2] += blue
            sums[key] = running
        }
        // A cover that is nearly all paper, ink and grey has no accent rather than a
        // faint one. A tenth is the line: below it the "dominant" colour is a logo.
        let counted = counts.values.reduce(0, +)
        guard counted * 10 >= pixels.count, counted > 0 else { return nil }
        // Lowest key breaks a tie, so the same cover gives the same colour on every
        // run and on both platforms. A dictionary's own order does not.
        guard let winner = counts.keys
            .max(by: { (counts[$0] ?? 0, -$0) < (counts[$1] ?? 0, -$1) }),
            let total = counts[winner], let sum = sums[winner] else { return nil }
        return hex(sum[0] / total, sum[1] / total, sum[2] / total)
    }

    /// Whether a pixel votes at all.
    ///
    /// Paper, ink and everything close to them are abstentions: they are what a page
    /// is made of rather than what it is coloured, and counting them means every
    /// cover resolves to off-white.
    private static func carriesColour(_ red: Int, _ green: Int, _ blue: Int) -> Bool {
        let highest = max(red, max(green, blue))
        let lowest = min(red, min(green, blue))
        return highest - lowest >= 24 && highest >= 24 && lowest <= 232
    }

    /// `hex`, lightened or darkened until it clears `ratio` against `background`.
    ///
    /// `nil` when no lightness of it can — a mid-grey background has no colour at all
    /// that reaches 4.5:1, which is a fact about contrast rather than a search giving
    /// up early. Refusing beats returning the nearest miss: the whole point of the
    /// adjustment is that what comes out of it is legible.
    ///
    /// Both directions are tried and the smaller move wins, so an accent stays as
    /// close to the artwork as the floor allows. Darkening scales the channels, which
    /// holds the hue exactly; lightening blends toward white, which is what a tint is.
    public static func legible(
        _ hex: String,
        on background: String,
        ratio: Double = floor
    ) -> String? {
        guard let channels = channels(of: hex) else { return nil }
        for step in 0...20 {
            let amount = Double(step) / 20
            for candidate in [darkened(channels, by: amount), lightened(channels, by: amount)]
            where ReadingContrast.ratio(candidate, background) >= ratio {
                return candidate
            }
        }
        return nil
    }

    /// The whole answer for one cover, or `nil` if it has none to give.
    ///
    /// The one entry point a screen should use, and the reason it returns an optional
    /// rather than something with a default baked in: `native-experience` puts the
    /// brand accent on "a surface with no publication context", and a cover that
    /// yields no colour has put the screen in exactly that position. The fallback is
    /// the caller's own accent, applied once where it is known.
    public static func derived(from pixels: [UInt32]) -> CoverColours? {
        guard let dominant = dominant(of: pixels),
              let wash = wash(from: pixels),
              let accent = legible(dominant, on: wash) else { return nil }
        return CoverColours(
            wash: wash,
            accent: accent,
            onAccent: ReadingContrast.bestForeground(on: accent).hex
        )
    }

    /// A background wash of the cover's colour, dark enough to carry white text.
    ///
    /// The other half of "accent **and background tinting** derive from the cover".
    /// Darkened rather than used raw for the same reason the accent is adjusted: the
    /// end-of-publication screen puts white text on this, and a pale cover would put
    /// white on cream. `nil` when the cover has no colour, so the caller keeps black.
    public static func wash(from pixels: [UInt32]) -> String? {
        guard let dominant = dominant(of: pixels),
              let channels = channels(of: dominant) else { return nil }
        for step in 0...20 {
            let candidate = darkened(channels, by: Double(step) / 20)
            if ReadingContrast.ratio(candidate, "#FFFFFF") >= ReadingContrast.aa { return candidate }
        }
        return nil
    }

    private static func darkened(_ channels: [Int], by amount: Double) -> String {
        let scale = 1 - amount
        return hex(
            Int(Double(channels[0]) * scale),
            Int(Double(channels[1]) * scale),
            Int(Double(channels[2]) * scale)
        )
    }

    private static func lightened(_ channels: [Int], by amount: Double) -> String {
        func blend(_ channel: Int) -> Int { channel + Int(Double(255 - channel) * amount) }
        return hex(blend(channels[0]), blend(channels[1]), blend(channels[2]))
    }

    private static func hex(_ red: Int, _ green: Int, _ blue: Int) -> String {
        String(format: "#%02X%02X%02X", clamp(red), clamp(green), clamp(blue))
    }

    private static func clamp(_ channel: Int) -> Int { min(255, max(0, channel)) }

    private static func channels(of hex: String) -> [Int]? {
        let text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
    }
}

/// What one cover gives its own screens.
///
/// Both `#rrggbb`, and both already adjusted: `native-experience` requires the derived
/// colour to be "adjusted until it meets the contrast floor in the design tokens, rather
/// than being used raw", so a value of this type is by construction legible — the wash
/// against the white text on it, the accent against the wash.
public struct CoverColours: Sendable, Equatable {
    /// The background tint, dark enough to carry white text.
    public let wash: String
    /// The accent, clear of the floor against ``wash``.
    public let accent: String
    /// What to write *on* the accent. Black or white, whichever the accent carries.
    public let onAccent: String

    public init(wash: String, accent: String, onAccent: String) {
        self.wash = wash
        self.accent = accent
        self.onAccent = onAccent
    }
}

extension CoverAccent {
    /// The cover, sampled down to the census grid.
    ///
    /// Drawn into a fixed 32×32 rather than scaled proportionally: the aspect ratio
    /// of a colour census means nothing, and a fixed grid makes the cost the same for
    /// a thumbnail and for a 2000×3000 scan. Interpolation off, so this point-samples
    /// the grid Android's row walk samples rather than averaging around each point —
    /// two censuses of the same cover have to agree.
    ///
    /// `nil` when the image cannot be drawn at all, which the caller reads the same
    /// way as a cover with no colour — the brand accent.
    public static func pixels(of image: CGImage) -> [UInt32]? {
        let edge = sampleEdge
        var bytes = [UInt8](repeating: 0, count: edge * edge * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let layout = CGImageAlphaInfo.noneSkipLast.rawValue
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: edge,
                      height: edge,
                      bitsPerComponent: 8,
                      bytesPerRow: edge * 4,
                      space: space,
                      bitmapInfo: layout
                  )
            else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))
            return true
        }
        guard drawn else { return nil }
        return stride(from: 0, to: bytes.count, by: 4).map { offset in
            UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2])
        }
    }
}
