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
    /// Longest signature we need to see. Reading more than this is wasted I/O,
    /// which matters when the file is on the far end of an SMB share.
    public static let probeLength = 8

    private static let zip: [UInt8] = [0x50, 0x4B]                                     // PK
    private static let rar4: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]      // Rar!..\0
    private static let rar5: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
    private static let sevenZip: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]        // 7z¼¯'\u{1C}
    private static let pdf: [UInt8] = [0x25, 0x50, 0x44, 0x46]                         // %PDF

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
        // TAR has no leading magic — its signature sits at offset 257 — so a
        // `.cbt` is identified by extension and confirmed by a successful parse.
        return nil
    }

    public enum Container: String, Sendable {
        case zip, rar, sevenZip, pdf
    }

    /// Reads only `probeLength` bytes from the head of a file.
    public static func container(ofFileAt url: URL) throws -> Container? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: probeLength) else { return nil }
        return container(of: data)
    }
}
