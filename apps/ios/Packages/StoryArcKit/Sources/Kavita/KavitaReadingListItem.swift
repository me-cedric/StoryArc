public import Foundation

/// One entry in a server reading list, in the order the server keeps.
public struct KavitaReadingListItem: Sendable, Equatable, Identifiable, Decodable {
    public let id: Int
    public let order: Int
    public let seriesId: Int
    public let chapterId: Int
    public let title: String?
    public let seriesName: String?
    /// How far into this entry the server says the reader has gone.
    public let pagesRead: Int
    /// How many pages the entry has, as the server counts them.
    ///
    /// Zero is the server saying nothing rather than an empty chapter, and
    /// `collections-and-reading-lists` asks for nothing to be claimed in that case. It is
    /// the only honest signal: `pagesRead` is zero for an unread entry as well.
    public let pagesTotal: Int
    /// The volume this entry's chapter sits in, which ``KavitaOrigin`` needs to name where
    /// a position or a mark goes on the server.
    public let volumeId: Int
    /// The library this entry's chapter sits in, for the same reason.
    public let libraryId: Int
    /// How large the entry's file is, in bytes, or zero where the server said nothing.
    ///
    /// Kavita's `ReadingListItemDto.fileSize`. A whole-shelf download adds these up to state
    /// its size before it starts, and zero is "not stated" rather than an empty file.
    public let fileSize: Int64

    /// What to call it in a list. The chapter's own title, or the series it belongs to.
    public var displayName: String {
        if let title, !title.isEmpty { return title }
        return seriesName ?? ""
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        seriesId = try container.decodeIfPresent(Int.self, forKey: .seriesId) ?? 0
        chapterId = try container.decodeIfPresent(Int.self, forKey: .chapterId) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title)
        seriesName = try container.decodeIfPresent(String.self, forKey: .seriesName)
        pagesRead = try container.decodeIfPresent(Int.self, forKey: .pagesRead) ?? 0
        pagesTotal = try container.decodeIfPresent(Int.self, forKey: .pagesTotal) ?? 0
        volumeId = try container.decodeIfPresent(Int.self, forKey: .volumeId) ?? 0
        libraryId = try container.decodeIfPresent(Int.self, forKey: .libraryId) ?? 0
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, order, seriesId, chapterId, title, seriesName, pagesRead, pagesTotal
        case volumeId, libraryId, fileSize
    }
}
