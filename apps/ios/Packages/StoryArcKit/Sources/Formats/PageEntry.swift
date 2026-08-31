internal import Foundation

/// One page inside a publication, before it is decoded.
public struct PageEntry: Sendable, Equatable, Identifiable {
    /// The entry's path inside the archive. Unique, so it is the identity.
    public let path: String
    /// Uncompressed size in bytes, where the container reports one.
    public let byteCount: Int?

    public var id: String { path }

    public init(path: String, byteCount: Int? = nil) {
        self.path = path
        self.byteCount = byteCount
    }
}

/// Which archive entries are pages, and in what order.
///
/// This is the part of the format layer most likely to disagree between the two
/// platforms, so it is pure, dependency-free, and asserted against the shared
/// fixture corpus on both.
public enum PageOrdering {
    /// Image extensions StoryArc will attempt to decode. A file outside this set
    /// is never a page — `publication-formats` requires `ComicInfo.xml`,
    /// `Thumbs.db` and resource forks to be excluded rather than shown blank.
    ///
    /// `jxl` is in the list although neither platform's decoder reads it, and that is
    /// deliberate: `publication-formats` requires an unsupported codec to show "a
    /// placeholder naming the codec" without breaking pagination, and a page excluded
    /// from the list is a page nobody can be told about. It is listed so it can be
    /// refused by name — see ``PageCodec``.
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "avif", "gif", "heic", "heif", "bmp", "tif", "tiff",
        "jxl",
    ]

    /// True when an entry could be part of a publication at all.
    ///
    /// Everything ``isPage(path:)`` rejected before it looked at the extension, split
    /// out so ``FolderKind`` can apply the same exclusions to audio without restating
    /// them. A resource fork is not evidence of a comic and not evidence of an
    /// audiobook either, and two copies of that list would eventually disagree.
    public static func isCandidateEntry(path: String) -> Bool {
        // Directory markers are not entries.
        guard !path.hasSuffix("/") else { return false }

        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let name = components.last else { return false }

        // macOS resource forks travel inside archives made on a Mac and mirror
        // every real page, so an archive would report double its page count.
        if components.contains(where: { $0 == "__MACOSX" || $0 == "__MACOSX/" }) { return false }
        if name.hasPrefix("._") { return false }
        // Dotfiles: .DS_Store and friends.
        if name.hasPrefix(".") { return false }
        return true
    }

    /// True when an entry is a page candidate.
    public static func isPage(path: String) -> Bool {
        guard isCandidateEntry(path: path) else { return false }
        let name = String(path.split(separator: "/", omittingEmptySubsequences: true).last ?? "")
        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    /// Sorts entries the way a human would: `page10` after `page9`, and chapter
    /// directories in order, by comparing the full path.
    public static func sorted(_ entries: [PageEntry]) -> [PageEntry] {
        entries.sorted { naturalCompare($0.path, $1.path) }
    }

    /// Filters to pages, then sorts. The whole job in one call.
    public static func pages(from paths: [String]) -> [PageEntry] {
        sorted(paths.filter(isPage).map { PageEntry(path: $0) })
    }

    /// Natural-order comparison: runs of digits compare numerically, everything
    /// else compares case-insensitively.
    ///
    /// Written by hand rather than using `localizedStandardCompare` because that
    /// is locale-sensitive, and page order inside an archive must not depend on
    /// the reader's language.
    public static func naturalCompare(_ lhs: String, _ rhs: String) -> Bool {
        var left = Substring(lhs)
        var right = Substring(rhs)

        while let leftChar = left.first, let rightChar = right.first {
            let leftIsDigit = leftChar.isNumber
            let rightIsDigit = rightChar.isNumber

            if leftIsDigit && rightIsDigit {
                let leftRun = left.prefix(while: \.isNumber)
                let rightRun = right.prefix(while: \.isNumber)
                // Compared digit-by-digit rather than parsed into an integer:
                // parsing caps at the platform's word size, and iOS's UInt64 and
                // Android's Long do not have the same ceiling. A page number is
                // never that long, but a latent divergence between the two
                // implementations is exactly what this layer must not have.
                let leftDigits = leftRun.drop(while: { $0 == "0" })
                let rightDigits = rightRun.drop(while: { $0 == "0" })
                if leftDigits.count != rightDigits.count {
                    return leftDigits.count < rightDigits.count
                }
                if leftDigits != rightDigits {
                    return leftDigits.lexicographicallyPrecedes(rightDigits)
                }
                // Same value. Fewer leading zeros sorts first, so the order is total.
                if leftRun.count != rightRun.count { return leftRun.count < rightRun.count }
                left = left.dropFirst(leftRun.count)
                right = right.dropFirst(rightRun.count)
                continue
            }

            if leftIsDigit != rightIsDigit {
                // A digit sorts before a letter, so `p1` precedes `pa`.
                return leftIsDigit
            }

            let leftLower = Character(leftChar.lowercased())
            let rightLower = Character(rightChar.lowercased())
            if leftLower != rightLower { return leftLower < rightLower }
            left = left.dropFirst()
            right = right.dropFirst()
        }

        return left.count < right.count
    }
}
