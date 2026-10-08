internal import SwiftUI
internal import UniformTypeIdentifiers

/// The exported library as a file the system document picker writes.
///
/// `library-portability` / *The export goes somewhere the reader picked*: the app writes no
/// file of its own. The bytes live in memory until `fileExporter` hands them to the place the
/// reader chose, and nowhere else.
struct LibraryFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    /// The one thing written: the bytes, as a single regular file.
    func wrapper() -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        wrapper()
    }

    /// The name the picker offers, dated so two exports do not overwrite each other.
    static func defaultName(on date: Date) -> String {
        "StoryArc library \(date.formatted(.iso8601.year().month().day()))"
    }
}
