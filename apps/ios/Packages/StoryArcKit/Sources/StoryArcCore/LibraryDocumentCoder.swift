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
    /// - Parameter transforms: the chain, injectable so a test can prove it runs. Production
    ///   passes ``transforms``.
    public static func decode(
        _ data: Data,
        transforms: [LibraryDocumentTransform] = LibraryDocumentCoder.transforms
    ) throws -> LibraryDocument {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let declared = parsed["formatVersion"] as? Int
        else { throw LibraryDocumentFailure.notALibraryDocument }

        let current = LibraryDocument.currentFormatVersion
        guard declared <= current else {
            throw LibraryDocumentFailure.newerThanThisApp(found: declared, understood: current)
        }

        let migrated = try migrating(parsed, from: declared, to: current, through: transforms)
        let body = try JSONSerialization.data(withJSONObject: migrated)

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
    /// before the reader is shown a list of what it would have done.
    public static func declaredVersion(of data: Data) -> Int? {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parsed["formatVersion"] as? Int
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

    private static func migrating(
        _ document: [String: Any],
        from declared: Int,
        to current: Int,
        through transforms: [LibraryDocumentTransform]
    ) throws -> [String: Any] {
        var migrated = document
        var version = declared
        while version < current {
            guard let step = transforms.first(where: { $0.from == version }) else {
                throw LibraryDocumentFailure.noMigrationPath(from: version)
            }
            migrated = step(migrated)
            version += 1
        }
        return migrated
    }
}
