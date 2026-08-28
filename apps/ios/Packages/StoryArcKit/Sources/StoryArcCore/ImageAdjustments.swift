/// What to do to a page before it is shown.
///
/// `comic-reader`: "per-publication image adjustments for poorly scanned material",
/// offering "brightness, contrast, sharpness, colour inversion, and greyscale ... with a
/// live preview". A scan too dark to read, or grey where it should be white, is the ordinary
/// state of a lot of comics, and a reader who cannot fix it has to stop reading.
///
/// The three continuous values are signed and neutral at zero, so ``isNeutral`` is a
/// comparison against a fresh value rather than a list of magic numbers, and a stored
/// adjustment that does nothing is indistinguishable from none.
public struct ImageAdjustments: Sendable, Equatable, Codable {
    /// −1 (black) to 1 (white), 0 unchanged.
    public var brightness: Double
    /// −1 (flat) to 1 (hard), 0 unchanged.
    public var contrast: Double
    /// 0 to 1. Not signed: blurring a scan is not a repair anyone asks for.
    public var sharpness: Double
    /// White on black. For a scan whose page is already dark, and for reading at night.
    public var isInverted: Bool
    /// Colour removed. A colour cover in a black-and-white run is a distraction, and a
    /// badly colour-cast scan reads better without the cast.
    public var isGreyscale: Bool
    /// Uniform white or black margins trimmed, page by page. See ``BorderCrop``.
    public var cropsBorders: Bool

    public init(
        brightness: Double = 0,
        contrast: Double = 0,
        sharpness: Double = 0,
        isInverted: Bool = false,
        isGreyscale: Bool = false,
        cropsBorders: Bool = false
    ) {
        self.brightness = brightness.clamped(to: -1 ... 1)
        self.contrast = contrast.clamped(to: -1 ... 1)
        self.sharpness = sharpness.clamped(to: 0 ... 1)
        self.isInverted = isInverted
        self.isGreyscale = isGreyscale
        self.cropsBorders = cropsBorders
    }

    /// Nothing to do. Worth asking, because applying a no-op filter still costs a redraw of
    /// every page.
    public var isNeutral: Bool { self == ImageAdjustments() }

    /// Decodes what is there and defaults what is not, for the reason ``ShelfSettings`` does.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            brightness: try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0,
            contrast: try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
            sharpness: try container.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0,
            isInverted: try container.decodeIfPresent(Bool.self, forKey: .isInverted) ?? false,
            isGreyscale: try container.decodeIfPresent(Bool.self, forKey: .isGreyscale) ?? false,
            cropsBorders: try container.decodeIfPresent(Bool.self, forKey: .cropsBorders) ?? false
        )
    }
}

extension ImageAdjustments {
    /// The multiplier a renderer wants for contrast, where 1 is unchanged.
    ///
    /// A signed −1…1 is what a reader drags; a 0…2 multiplier is what every image pipeline
    /// takes. Kept here rather than in each renderer so iOS and Android cannot drift.
    public var contrastFactor: Double { 1 + contrast }

    /// The offset a renderer wants for brightness, in the same units as the pixel values.
    public var brightnessOffset: Double { brightness }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
