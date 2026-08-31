public import Foundation

public import StoryArcCore

// `PublicationFormat` used to live here. It moved to `StoryArcCore`: the library
// sorts, filters and explains by format, and none of that should require the
// parser. This file keeps the sniffer, which is genuinely format-layer work.

/// What a file's leading bytes say it is, regardless of its name.
public enum FormatSniffer {
    /// Longest signature we need to see.
    ///
    /// TAR sets the floor: its `ustar` magic sits at offset 257, where every
    /// other container announces itself in the first eight bytes. 265 bytes is
    /// still one round trip on an SMB share, which is the cost that matters —
    /// reading 8 instead would save nothing and lose CBT detection.
    public static let probeLength = 265

    private static let zip: [UInt8] = [0x50, 0x4B]                                     // PK
    private static let rar4: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]      // Rar!..\0
    private static let rar5: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
    private static let sevenZip: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]        // 7z¼¯'\u{1C}
    private static let pdf: [UInt8] = [0x25, 0x50, 0x44, 0x46]                         // %PDF
    private static let ustar: [UInt8] = [0x75, 0x73, 0x74, 0x61, 0x72]                 // ustar, at offset 257
    private static let id3: [UInt8] = [0x49, 0x44, 0x33]                               // ID3
    private static let flac: [UInt8] = [0x66, 0x4C, 0x61, 0x43]                        // fLaC
    private static let oggS: [UInt8] = [0x4F, 0x67, 0x67, 0x53]                        // OggS
    private static let ftyp: [UInt8] = [0x66, 0x74, 0x79, 0x70]                        // ftyp, at offset 4

    /// Where an MPEG-4 file states its brand: the four bytes after `ftyp`.
    private static let brandOffset = 8

    /// The brands that mean a store's content protection rather than a format.
    ///
    /// Audible's two. They are checked as brands rather than as file extensions
    /// because `publication-formats` says the contents are the fact — a `.m4b`
    /// renamed from an `.aax` is still locked, and refusing on the extension alone
    /// would let it through to a decoder that then reports a damaged file.
    private static let protectedBrands: Set<String> = ["aax ", "aaxc"]

    /// The container a byte prefix identifies, or `nil` when nothing matches.
    ///
    /// EPUB and CBZ are both ZIP; distinguishing them needs the archive's
    /// contents, which is why this returns `.zip` and the caller resolves it.
    public static func container(of prefix: some Collection<UInt8>) -> Container? {
        let bytes = Array(prefix)
        func starts(with signature: [UInt8]) -> Bool {
            bytes.count >= signature.count && Array(bytes.prefix(signature.count)) == signature
        }
        if starts(with: rar5) || starts(with: rar4) { return .rar }
        if starts(with: sevenZip) { return .sevenZip }
        if starts(with: pdf) { return .pdf }
        if starts(with: zip) { return .zip }
        if starts(with: flac) { return .flac }
        if starts(with: oggS) { return .ogg }
        // MPEG-4 announces itself at offset 4, and its *brand* at offset 8 is what
        // separates an audiobook from a locked one. A file whose brand is a store's
        // protection is refused for being locked rather than for being the wrong
        // kind of file, which `publication-formats` requires to be a distinct
        // refusal — hence a distinct case rather than a flag a caller may forget.
        if bytes.count >= brandOffset + 4,
           Array(bytes[4..<brandOffset]) == ftyp {
            let name = brand(bytes[brandOffset..<(brandOffset + 4)]) ?? ""
            return protectedBrands.contains(name) ? .protectedAudiobook : .mp4
        }
        if starts(with: id3) { return .mp3 }
        // A bare MPEG frame: eleven sync bits, and a layer field that is not the
        // reserved `00`. Without the layer check every byte pair from 0xFFE0 up
        // matches, and a truncated ZIP happens to contain plenty of those.
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] & 0xE0 == 0xE0, bytes[1] & 0x06 != 0 {
            return .mp3
        }
        // TAR announces itself at offset 257 rather than at the start, so it is
        // checked last and only when the probe reached that far.
        if bytes.count >= TarReader.magicOffset + ustar.count,
           Array(bytes[TarReader.magicOffset..<(TarReader.magicOffset + ustar.count)]) == ustar {
            return .tar
        }
        return nil
    }

    /// Four bytes of ASCII as a `String`, for reading an MPEG-4 brand.
    ///
    /// A brand is ASCII by definition, so a header carrying anything else fails to
    /// decode and returns `nil` — which then matches no known brand, the right
    /// outcome for a damaged file.
    private static func brand(_ bytes: some Sequence<UInt8>) -> String? {
        String(bytes: Array(bytes), encoding: .ascii)
    }

    public enum Container: String, Sendable {
        case zip, rar, sevenZip, pdf, tar
        case mp4, mp3, flac, ogg
        /// An MPEG-4 file whose brand declares a store's content protection.
        ///
        /// Its own case, because `publication-formats` requires the refusal to be
        /// "distinct from an unsupported container": the format is supported and
        /// this particular file is locked, and those two need different words.
        case protectedAudiobook

        /// Whether a player rather than a reader opens this.
        ///
        /// Asked here rather than at each call site, because a `switch` repeated at
        /// three call sites is how two of them end up disagreeing. Protected audio
        /// answers `true`: it is refused for being locked, not for being the wrong
        /// kind of file, and a caller that routed it to a comic reader would produce
        /// the unsupported-container message this spec forbids for it.
        public var isAudio: Bool {
            switch self {
            case .mp4, .mp3, .flac, .ogg, .protectedAudiobook: true
            case .zip, .rar, .sevenZip, .pdf, .tar: false
            }
        }

        /// How the container is named to the user when StoryArc refuses it.
        ///
        /// `publication-formats` forbids a generic parse failure: someone handed
        /// a 7-Zip comic to a comic reader and deserves to be told that, not
        /// that the file is broken. These are format names rather than prose, so
        /// the localised string wraps them.
        public var displayName: String {
            switch self {
            case .zip: "ZIP"
            case .rar: "RAR"
            case .sevenZip: "7-Zip"
            case .pdf: "PDF"
            case .tar: "TAR"
            case .mp4: "MPEG-4 audio"
            case .mp3: "MP3"
            case .flac: "FLAC"
            case .ogg: "Ogg"
            case .protectedAudiobook: "protected audiobook"
            }
        }
    }

    /// Reads only `probeLength` bytes from the head of a file.
    public static func container(ofFileAt url: URL) throws -> Container? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: probeLength) else { return nil }
        return container(of: data)
    }
}
