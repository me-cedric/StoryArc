public import Foundation

/// The book being read, as a home-screen widget shows it.
///
/// ADR-0011, prerequisite 1. A widget is a second process: it cannot open the progress store
/// or the cover cache. So the app writes this small record whenever the book it would offer
/// to continue changes, and the widget reads this record and nothing else.
///
/// It is the same fact ``QuickActions/offered(continuing:hasDownloads:)`` names in the
/// launcher menu, with the series and the part read added. Android's `ReadingSnapshot`
/// mirrors it case for case.
public struct ReadingSnapshot: Sendable, Equatable {

    /// The format of the stored record. A record in any other format is not read.
    public static let version = 1

    /// The App Group both the app and the widget extension name. `project.yml` and the three
    /// entitlement files must name the same group; `WidgetSigningTests` checks it.
    public static let appGroup = "group.com.mecedric.storyarc"

    /// The widget's kind, which WidgetKit stores with every widget on a home screen.
    public static let widgetKind = "app.storyarc.widget.reading"

    /// The longest side of the stored cover, in pixels. A medium widget is about 155 points
    /// high, so this is a 3x screen with a small margin.
    public static let coverPixels = 480

    public let publicationID: String
    public let title: String
    public let series: String?
    /// The whole percent read, from 0 to 100. `nil` for a publication with no position.
    public let percentRead: Int?

    /// The snapshot of the book to continue, or `nil` when there is none.
    ///
    /// A publication with no usable title gives no snapshot, for the reason
    /// ``QuickActions`` gives: a widget headed by a blank line names no book.
    ///
    /// The percent is rounded down, so 99.6 percent shows 99 and only a finished book shows
    /// 100. It also means a page turn that does not move the whole percent writes nothing.
    public init?(publication: Publication?, fractionRead: Double?) {
        guard let publication else { return nil }
        let title = publication.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        self.init(
            publicationID: publication.id,
            title: title,
            series: publication.series,
            percentRead: fractionRead.map { Int(($0 * 100).rounded(.down)) }
        )
    }

    init(publicationID: String, title: String, series: String?, percentRead: Int?) {
        self.publicationID = publicationID
        self.title = title
        let series = series?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.series = series?.isEmpty == false ? series : nil
        self.percentRead = percentRead.map { min(max($0, 0), 100) }
    }

    /// The part read, from 0 to 1, for a progress bar.
    public var fractionRead: Double? { percentRead.map { Double($0) / 100 } }

    /// The file name of this publication's cover, in the snapshot's folder.
    ///
    /// Named from the publication, so a cover can never be shown under another book's title:
    /// a snapshot for a new book looks for a new file, and finds nothing until the app has
    /// written it.
    public var coverFile: String { Self.coverFile(for: publicationID) }

    /// The cover file name for a publication identifier.
    ///
    /// An identifier holds a path, so it cannot be a file name. FNV-1a over its UTF-8 bytes
    /// gives a short stable name, and Android computes the same name for the same identifier.
    public static func coverFile(for publicationID: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in publicationID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return "cover-" + String(repeating: "0", count: 16 - hex.count) + hex + ".jpg"
    }

    /// The URL scheme the app declares, so a tap on the widget reaches it.
    public static let urlScheme = "storyarc"

    /// What a tap on the widget opens: the book, or the library when no book is shown.
    ///
    /// ``QuickActionRequest/init(widgetURL:)`` reads it back, so a widget tap takes the
    /// same path as the launcher menu's entries.
    public static func link(to snapshot: ReadingSnapshot?) -> URL {
        var components = URLComponents()
        components.scheme = urlScheme
        if let snapshot {
            components.host = "continue"
            components.queryItems = [URLQueryItem(name: "publication", value: snapshot.publicationID)]
        } else {
            components.host = "library"
        }
        // A scheme, a fixed host and one encoded query item always make a URL.
        return components.url ?? URL(filePath: "/")
    }

    /// The stored form.
    public func encoded() throws -> Data {
        try JSONEncoder().encode(
            Stored(
                version: Self.version,
                publicationID: publicationID,
                title: title,
                series: series,
                percentRead: percentRead
            )
        )
    }

    /// Reads a stored record back. `nil` for a record that is malformed, in another format,
    /// or that names no publication or no title.
    public static func decoded(_ data: Data) -> ReadingSnapshot? {
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == version,
              !stored.publicationID.isEmpty,
              !stored.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return ReadingSnapshot(
            publicationID: stored.publicationID,
            title: stored.title,
            series: stored.series,
            percentRead: stored.percentRead
        )
    }

    private struct Stored: Codable {
        let version: Int
        let publicationID: String
        let title: String
        let series: String?
        let percentRead: Int?
    }
}
