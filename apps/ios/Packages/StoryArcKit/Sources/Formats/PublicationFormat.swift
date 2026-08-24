public import Foundation

/// The container formats StoryArc can open.
///
/// `publication-formats` requires format to be determined from a file's
/// contents, not its extension — a ZIP called `.cbr` still opens. The extension
/// is only ever a hint used to order the sniffing.
public enum PublicationFormat: String, Sendable, CaseIterable {
    case cbz, cbr, cb7, cbt, epub, pdf, imageFolder

    /// Whether pages are images rather than reflowable text. Drives which reader
    /// opens the publication, and whether a page curl needs a raster.
    public var isPagedImages: Bool {
        switch self {
        case .cbz, .cbr, .cb7, .cbt, .imageFolder: true
        case .epub, .pdf: false
        }
    }
}

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
        // TAR announces itself at offset 257 rather than at the start, so it is
        // checked last and only when the probe reached that far.
        if bytes.count >= TarReader.magicOffset + ustar.count,
           Array(bytes[TarReader.magicOffset..<(TarReader.magicOffset + ustar.count)]) == ustar {
            return .tar
        }
        return nil
    }

    public enum Container: String, Sendable {
        case zip, rar, sevenZip, pdf, tar

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
