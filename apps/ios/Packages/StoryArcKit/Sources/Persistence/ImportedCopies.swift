public import Foundation

public import StoryArcCore

/// A publication copied into storage the app owns.
///
/// `local-library`: the app "SHALL let a user import a publication into app-managed
/// storage, so that the copy survives the original being moved or deleted". The bytes go
/// where downloaded bytes already go. ``DownloadStore`` owns a directory that is made once,
/// kept out of backups, and totalled from the disk rather than from a record — a second
/// store for the same job would be a second place for the list and the files to disagree,
/// which is the failure that store exists to prevent.
///
/// What makes a copy an *import* is the source it is attributed to, not where it sits. So
/// the identifier of the "On this device" source is fixed rather than generated: the source
/// has to be the same one on the next launch, and a new identifier every launch would leave
/// a reader with a row of empty sources.
public enum ImportedCopies {
    /// The identity of the "On this device" source.
    ///
    /// Written as bytes rather than parsed from a string because parsing returns an
    /// optional and this codebase does not force-unwrap. It is the same value Android's
    /// `ImportedCopies.SOURCE_ID` parses: `9e0d1cef-0000-4000-8000-000000000001`.
    public static let sourceID = UUID(uuid: (
        0x9E, 0x0D, 0x1C, 0xEF, 0x00, 0x00, 0x40, 0x00,
        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
    ))

    /// Whether a record describes a copy the reader imported rather than one fetched from
    /// a source.
    ///
    /// Asked in three places that must treat the two differently: an import is never swept
    /// away by "remove downloads after finishing", it is attributed to a source the reader
    /// did not configure, and its removal says something a download's does not.
    public static func isImported(_ download: Download) -> Bool {
        download.sourceID == sourceID
    }

    /// What an imported copy is called in the record.
    ///
    /// The original's name and its size, so importing the same file twice is one copy
    /// rather than two rows of the same book. Deliberately not the original's path: the
    /// requirement is that the copy "survives the original being moved or deleted", and a
    /// path-keyed identity would make a moved original a second import of the same comic.
    public static func identity(name: String, bytes: Int64) -> String {
        "imported:\(name):\(bytes)"
    }

    /// Why an import did not happen.
    public enum ImportError: Error, Equatable {
        /// The file is not in a format StoryArc reads. Carries the format's own name,
        /// because `local-library` forbids a refusal that does not say what it refused.
        case unsupported(String)
        /// The bytes could not be read, or could not be written.
        case unreadable
    }
}

/// What an import produced: the new record, the file it landed in, and the library holding
/// it. All three together because they are one act — a record without its file is a library
/// that lost a book, and a file without its record is bytes nothing can find.
public struct ImportedCopy: Sendable {
    public let library: DownloadLibrary
    public let download: Download
    public let file: URL

    /// What the copy weighs, which is what `local-library` asks the app to report.
    public var bytes: Int64 { download.downloadedBytes }
}

extension DownloadStore {
    /// Copies a publication into app storage and records it.
    ///
    /// Importing the same file twice is one copy: the record is keyed on the original's
    /// name and size, and ``DownloadLibrary/queueing(_:)`` already refuses a second row for
    /// an identifier it holds. A reader who taps Import on a comic they imported last week
    /// gets the copy they already have rather than a second one beside it.
    ///
    /// The original is only read. `local-library` promises the copy survives the original
    /// "being moved or deleted", which it can only do if it never owned it in the first
    /// place.
    public func importing(_ original: URL, into library: DownloadLibrary) throws -> ImportedCopy {
        // A URL from the document picker points outside the sandbox and is unreadable
        // until its scope is opened. Balanced here rather than by the caller because this
        // is the only code that reads the bytes.
        let scoped = original.startAccessingSecurityScopedResource()
        defer { if scoped { original.stopAccessingSecurityScopedResource() } }

        let ext = original.pathExtension.lowercased()
        guard let format = PublicationFormat(rawValue: ext), let mediaType = format.mediaType
        else {
            throw ImportedCopies.ImportError.unsupported(
                ext.isEmpty ? original.lastPathComponent : ext.uppercased()
            )
        }

        let name = original.lastPathComponent
        let values = try? original.resourceValues(forKeys: [.fileSizeKey])
        guard let bytes = values?.fileSize.map(Int64.init) else {
            throw ImportedCopies.ImportError.unreadable
        }

        let id = ImportedCopies.identity(name: name, bytes: bytes)
        let stem = original.deletingPathExtension().lastPathComponent
        let file = location(for: id, extension: ext, named: stem)

        // Already here, so the copy is the one the reader already has. Checked before the
        // filesystem work rather than after it: a second `copyItem` onto an existing path
        // fails, and the reader would be told the import broke when nothing did.
        if let existing = library[id], FileManager.default.fileExists(atPath: file.path) {
            return ImportedCopy(library: library, download: existing, file: file)
        }

        try prepare()
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Removed first: a record can be lost while its bytes survive — a crash between
            // the copy and the save — and `copyItem` onto an existing path throws.
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.copyItem(at: original, to: file)
        } catch {
            throw ImportedCopies.ImportError.unreadable
        }

        let record = Download(
            id: id,
            sourceID: ImportedCopies.sourceID,
            title: stem,
            // Where it came from, so a record can say what was imported. Never read back to
            // fetch anything: an import has nothing to retry.
            remote: original,
            mediaType: mediaType,
            expectedBytes: bytes,
            downloadedBytes: bytes
        )
        // Finished through the library's own vocabulary rather than by constructing the
        // state here, so the copy carries a completion date like every other row does.
        let saved = library.queueing(record).marking(id, as: .finished)
        save(saved)
        guard let stored = saved[id] else { throw ImportedCopies.ImportError.unreadable }
        return ImportedCopy(library: saved, download: stored, file: file)
    }

    /// Every copy the reader imported, largest first.
    ///
    /// Largest first because that is the order the question "what can I delete" is asked
    /// in, and it is the order the storage screen already lists what is on the device.
    public func imports(in library: DownloadLibrary) -> [Download] {
        library.finished
            .filter(ImportedCopies.isImported)
            .sorted { $0.downloadedBytes > $1.downloadedBytes }
    }
}
