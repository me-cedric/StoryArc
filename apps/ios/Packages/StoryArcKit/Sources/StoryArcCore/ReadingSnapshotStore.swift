public import Foundation

/// The folder a ``ReadingSnapshot`` and its cover live in.
///
/// The app writes, the widget reads. A file and not a database, so the widget's read is
/// one file read (ADR-0011). Android's `ReadingSnapshotStore` mirrors it.
public struct ReadingSnapshotStore: Sendable {

    public static let snapshotFile = "reading-snapshot.json"

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The store in the App Group container, or `nil` when the process has no such group.
    ///
    /// `nil` is what a build signed without the group gets. The widget then shows its empty
    /// state, and the app writes nothing.
    public static func shared() -> ReadingSnapshotStore? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ReadingSnapshot.appGroup)
            .map { ReadingSnapshotStore(folder: $0.appending(path: "Widget", directoryHint: .isDirectory)) }
    }

    private var snapshotURL: URL { folder.appending(path: Self.snapshotFile) }

    /// The stored snapshot, or `nil` when there is none or it cannot be read.
    public func read() -> ReadingSnapshot? {
        (try? Data(contentsOf: snapshotURL)).flatMap(ReadingSnapshot.decoded)
    }

    /// The cover of a snapshot's own publication, or `nil` when the app has not written one.
    public func cover(of snapshot: ReadingSnapshot) -> URL? {
        let url = folder.appending(path: snapshot.coverFile)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// Stores what the widget is to show, and says whether anything changed.
    ///
    /// `cover` is asked only when this publication has no cover file yet, because decoding a
    /// cover costs far more than this write. A `nil` snapshot removes everything, so a widget
    /// never names a book the library no longer offers. Covers of other publications are
    /// removed in every case.
    ///
    /// `false` means the stored state is already this one. The caller then has no reason to
    /// ask the system to redraw the widget, which WidgetKit counts against a budget.
    @discardableResult
    public func write(
        _ snapshot: ReadingSnapshot?,
        cover: @Sendable () async -> Data?
    ) async throws -> Bool {
        let files = FileManager.default
        var changed = false

        if let snapshot {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            if self.cover(of: snapshot) == nil, let data = await cover() {
                try data.write(to: folder.appending(path: snapshot.coverFile), options: .atomic)
                changed = true
            }
            if read() != snapshot {
                try snapshot.encoded().write(to: snapshotURL, options: .atomic)
                changed = true
            }
        } else if files.fileExists(atPath: snapshotURL.path(percentEncoded: false)) {
            try files.removeItem(at: snapshotURL)
            changed = true
        }

        let kept = snapshot?.coverFile
        let stale = ((try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [])
            .filter { $0.hasPrefix("cover-") && $0 != kept }
        for name in stale {
            try files.removeItem(at: folder.appending(path: name))
            changed = true
        }
        return changed
    }
}
