public import Foundation

/// A cover the reader chose, with the key the store files it under.
///
/// The key is ``PublicationIdentity/coverOverrideKey``: `sha:<digest>` where the publication
/// has a content digest, its stable identifier where it has none. Both platforms spell it the
/// same, which is what lets a cover chosen on one be found on the other.
public struct ChosenCover: Sendable, Equatable {
    public let key: String
    public let image: Data

    public init(key: String, image: Data) {
        self.key = key
        self.image = image
    }
}

/// Where chosen covers are kept, as far as an export and an import need to see.
///
/// A protocol in the core because the store itself lives in `Formats`, and `Persistence`, where
/// the archive reads and writes every other part of the library, cannot see `Formats`.
public protocol ChosenCoverStore: Sendable {
    /// Every chosen cover this store can name.
    ///
    /// The store names the ones it has filed with their key. `candidates` lets it find the ones
    /// chosen before it filed keys, by trying each key it is handed.
    func chosen(including candidates: [String]) -> [ChosenCover]

    func image(forKey key: String) -> Data?

    /// - Returns: whether the image was written.
    @discardableResult
    func store(_ image: Data, forKey key: String) -> Bool

    func remove(forKey key: String)
}

extension PublicationIdentity {

    /// The key a chosen cover for this publication is filed under.
    ///
    /// The content digest where there is one, because it survives a rename and a move; the
    /// stable identifier where there is none. `cover-for-every-publication` task 2.1.
    public var coverOverrideKey: String {
        contentDigest.map { "sha:\($0)" } ?? stableID
    }
}

/// One chosen cover as the document spells it: the store's own key and the image in base64.
///
/// design.md: "Only the covers a reader *chose* are images with no other source, and those are
/// few and base64 in the body is enough."
public struct DocumentCover: Sendable, Equatable, Codable {
    public var key: String
    public var image: String

    public init(key: String, image: String) {
        self.key = key
        self.image = image
    }
}
