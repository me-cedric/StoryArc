public import Foundation

/// Why a document could not be read.
///
/// `library-portability` / *A newer document is refused, by name*: the app "names the version
/// it found and the newest it understands, and changes nothing". A case carrying both numbers
/// rather than a formatted string, so the four languages each phrase it themselves.
public enum LibraryDocumentFailure: Error, Sendable, Equatable {
    /// The bytes are not a JSON object with a `formatVersion` in them.
    case notALibraryDocument

    /// The document declares a version this build does not know.
    ///
    /// Refused rather than partly read. An older app meeting a newer export can only guess at
    /// what it does not understand, and guessing changes data silently; refusing names the
    /// problem and leaves the device as it was.
    case newerThanThisApp(found: Int, understood: Int)

    /// A version this build should know, with no transform that reaches the current one.
    case noMigrationPath(from: Int)

    /// The document declared a known version and then did not match it.
    case malformed(String)

    /// The document holds more bytes than this build reads.
    ///
    /// Refused by name, before any parse, the way a newer version is. A file a reader was
    /// handed can be any size, and parsing is where the memory goes.
    case tooLarge(found: Int, limit: Int)
}

/// One step up the version ladder.
///
/// A transform over the parsed JSON rather than over a typed value, because the type it would
/// decode into is the one this build has and an older document is by definition not that
/// shape. `from` is the version it reads; it writes `from + 1`.
public struct LibraryDocumentTransform: Sendable {
    public let from: Int
    private let apply: @Sendable ([String: Any]) -> [String: Any]

    public init(from: Int, apply: @escaping @Sendable ([String: Any]) -> [String: Any]) {
        self.from = from
        self.apply = apply
    }

    public func callAsFunction(_ document: [String: Any]) -> [String: Any] {
        var migrated = apply(document)
        migrated["formatVersion"] = from + 1
        return migrated
    }
}

/// Reads and writes ``LibraryDocument``.
///
/// The version is checked before anything is decoded, because the whole point of refusing a
/// newer document is that nothing happens to the device — a decoder that got partway and then
/// threw would have already told its caller about half a library.
///
/// Android's `LibraryDocumentCoder` is the same three operations and the same refusals.
public enum LibraryDocumentCoder {

    /// The most bytes this build reads: 64 MiB.
    ///
    /// The text of a very large library is a few megabytes. The rest of the room is for the
    /// covers a reader chose, which travel as base64 (task 6.7): a few hundred of them fit.
    /// Android's `LibraryDocumentCoder.MAXIMUM_BYTES` holds the same number.
    public static let maximumBytes = 64 * 1024 * 1024

    /// The transforms this build ships. Empty: version 1 is the first, and the chain exists
    /// from the start so the second version has somewhere to go.
    public static let transforms: [LibraryDocumentTransform] = []

    /// The document as bytes a reader can open.
    ///
    /// Sorted keys and indentation because `library-portability` asks for a body a reader can
    /// open and a later version can diff, and a diff of two files whose keys are in a
    /// different order every time is not a diff anybody reads.
    public static func encode(_ document: LibraryDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    /// A document read back, migrated forward if it is older.
    ///
    /// The size is checked first, before a byte is parsed. A document of the current version
    /// decodes straight from `data`, so the bytes and the decoded value are the only two
    /// copies; only an older one is parsed into a tree to be migrated and written out again.
    ///
    /// - Parameter limit: the size ceiling, injectable so a test need not allocate 64 MiB.
    /// - Parameter transforms: the chain, injectable so a test can prove it runs. Production
    ///   passes ``transforms``.
    public static func decode(
        _ data: Data,
        limit: Int = LibraryDocumentCoder.maximumBytes,
        transforms: [LibraryDocumentTransform] = LibraryDocumentCoder.transforms
    ) throws -> LibraryDocument {
        guard data.count <= limit else {
            throw LibraryDocumentFailure.tooLarge(found: data.count, limit: limit)
        }
        guard let declared = declaredVersion(of: data, limit: limit)
        else { throw LibraryDocumentFailure.notALibraryDocument }

        let current = LibraryDocument.currentFormatVersion
        guard declared <= current else {
            throw LibraryDocumentFailure.newerThanThisApp(found: declared, understood: current)
        }

        let body = declared == current
            ? data
            : try migrated(data, from: declared, to: current, through: transforms)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.readingAMoment)
        do {
            return try decoder.decode(LibraryDocument.self, from: body)
        } catch {
            throw LibraryDocumentFailure.malformed(String(describing: error))
        }
    }

    /// The version a document declares, without decoding it.
    ///
    /// What an import preview asks first: a document it is going to refuse should be refused
    /// before the reader is shown a list of what it would have done. Nil also for a document
    /// over `limit`, which ``decode(_:limit:transforms:)`` refuses by name.
    public static func declaredVersion(
        of data: Data,
        limit: Int = LibraryDocumentCoder.maximumBytes
    ) -> Int? {
        guard data.count <= limit else { return nil }
        return (try? JSONDecoder().decode(DeclaredVersion.self, from: data))?.formatVersion
    }

    private struct DeclaredVersion: Decodable {
        let formatVersion: Int
    }

    /// An ISO 8601 moment, with or without a fraction of a second.
    ///
    /// Both platforms write whole seconds, and `ISO8601DateFormatter` refuses a fractional
    /// one outright unless it is told to expect it — so a document from anything that does
    /// write a fraction would be refused over a field no reader ever looks at. Two formatters
    /// and a fallthrough is the whole of the tolerance.
    private static func readingAMoment(_ decoder: any Decoder) throws -> Date {
        let text = try decoder.singleValueContainer().decode(String.self)
        let wholeSeconds = ISO8601DateFormatter()
        let fractionalSeconds = ISO8601DateFormatter()
        fractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for formatter in [wholeSeconds, fractionalSeconds] {
            if let moment = formatter.date(from: text) { return moment }
        }
        throw LibraryDocumentFailure.malformed("not an ISO 8601 moment: \(text)")
    }

    /// An older document, parsed, carried up the chain and written out again.
    private static func migrated(
        _ data: Data,
        from declared: Int,
        to current: Int,
        through transforms: [LibraryDocumentTransform]
    ) throws -> Data {
        guard var document = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw LibraryDocumentFailure.notALibraryDocument }
        var version = declared
        while version < current {
            guard let step = transforms.first(where: { $0.from == version }) else {
                throw LibraryDocumentFailure.noMigrationPath(from: version)
            }
            document = step(document)
            version += 1
        }
        do {
            return try JSONSerialization.data(withJSONObject: document)
        } catch {
            throw LibraryDocumentFailure.malformed(String(describing: error))
        }
    }
}
