public import Foundation

/// What a page's bytes say they are encoded with.
///
/// `publication-formats`: "a page in an unsupported codec displays a placeholder naming
/// the codec, and does not break pagination". Naming it is the whole job of this type,
/// and the name matters more than it looks: a placeholder that says nothing leaves a
/// reader unable to tell a file the app cannot read from a file that is broken. One
/// page saying "JPEG" among a hundred that decoded is a damaged entry; every page
/// saying "JPEG XL" is a format this device has no decoder for.
///
/// Read from the bytes rather than the extension, for the reason
/// ``FormatSniffer`` reads containers that way: a page named `.jpg` that is really
/// AVIF is common in files converted in bulk, and a name is not evidence.
///
/// Android's `PageCodec` is the same table, sniffed in the same order.
public enum PageCodec: String, Sendable, Equatable, CaseIterable {
    case jpeg, png, gif, webp, avif, heic, jpegXL, bmp, tiff

    /// How the codec is named to the reader.
    ///
    /// Format names rather than prose, so the localised sentence wraps them — exactly
    /// as `FormatSniffer.Container.displayName` does for a refused container.
    public var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .gif: "GIF"
        case .webp: "WebP"
        case .avif: "AVIF"
        case .heic: "HEIC"
        case .jpegXL: "JPEG XL"
        case .bmp: "BMP"
        case .tiff: "TIFF"
        }
    }

    /// Longest prefix any signature below needs. An ISO base-media brand sits at
    /// offset 8, so twelve bytes covers every case.
    public static let probeLength = 12

    /// The codec a byte prefix identifies, or `nil` when nothing matches.
    ///
    /// Ordered so that the unambiguous fixed signatures answer first and the two
    /// container-shaped families — RIFF and ISO base media — are reached only when
    /// nothing shorter matched.
    public static func of(_ prefix: some Collection<UInt8>) -> PageCodec? {
        let bytes = Array(prefix.prefix(probeLength))
        return fixedSignature(of: bytes) ?? container(of: bytes)
    }

    /// The codecs that announce themselves in their first bytes and nowhere else.
    private static func fixedSignature(of bytes: [UInt8]) -> PageCodec? {
        func starts(with signature: [UInt8]) -> Bool {
            bytes.count >= signature.count && Array(bytes.prefix(signature.count)) == signature
        }
        if starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if starts(with: [0x47, 0x49, 0x46, 0x38]) { return .gif }                      // GIF8
        if starts(with: [0x42, 0x4D]) { return .bmp }                                  // BM
        if starts(with: [0x49, 0x49, 0x2A, 0x00]) || starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return .tiff
        }
        // A naked JPEG XL codestream, and the ISO-BMFF container form.
        if starts(with: [0xFF, 0x0A]) { return .jpegXL }
        if starts(with: [0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A]) {
            return .jpegXL
        }
        return nil
    }

    /// The two codecs that live inside a general-purpose container, where the tag that
    /// says which is not at the start of the file.
    private static func container(of bytes: [UInt8]) -> PageCodec? {
        // RIFF....WEBP: the four bytes between are the chunk length, which is not a
        // signature and must not be compared.
        if ascii(bytes, at: 0) == "RIFF", ascii(bytes, at: 8) == "WEBP" { return .webp }
        // ISO base media: `ftyp` at offset 4, then the brand. AVIF and HEIC are the
        // same container with different brands, which is why one check answers both.
        guard ascii(bytes, at: 4) == "ftyp", let brand = ascii(bytes, at: 8) else { return nil }
        if avifBrands.contains(brand) { return .avif }
        if heicBrands.contains(brand) { return .heic }
        return nil
    }

    /// Four bytes at an offset, as ASCII, or `nil` when the prefix is too short.
    private static func ascii(_ bytes: [UInt8], at offset: Int) -> String? {
        guard bytes.count >= offset + 4 else { return nil }
        return String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii)
    }

    private static let avifBrands: Set<String> = ["avif", "avis"]
    /// `mif1` and `msf1` are the generic HEIF brands; the rest are HEVC-coded images.
    /// All of them arrive from a phone camera and all of them are called HEIC by the
    /// people who have one.
    private static let heicBrands: Set<String> = [
        "heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1",
    ]

    /// What to call a page that could not be decoded, given whatever is known about it.
    ///
    /// The bytes first, the extension second, and `nil` when neither says anything —
    /// because "this page could not be read" is a better sentence than a codec name
    /// invented from a file name nobody chose.
    public static func name(of data: Data?, path: String) -> String? {
        if let data, let codec = of(data) { return codec.displayName }
        let ext = (path as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return byExtension[ext]?.displayName
    }

    /// The extensions `PageOrdering` will attempt, mapped to what they claim to be.
    private static let byExtension: [String: PageCodec] = [
        "jpg": .jpeg, "jpeg": .jpeg, "png": .png, "gif": .gif, "webp": .webp,
        "avif": .avif, "heic": .heic, "heif": .heic, "jxl": .jpegXL,
        "bmp": .bmp, "tif": .tiff, "tiff": .tiff,
    ]
}
