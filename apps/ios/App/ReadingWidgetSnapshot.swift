import OSLog
import WidgetKit

import LibraryFeature
import StoryArcCore

/// Writes the home-screen widget's snapshot, and asks WidgetKit to redraw when it changed.
///
/// ADR-0011: the widget reads ``ReadingSnapshot`` and nothing else. `ReadingContinuity` calls
/// this whenever the first book it would continue, or that book's whole percent, changes.
@MainActor
enum ReadingWidgetSnapshot {

    private static let log = Logger(subsystem: "app.storyarc", category: "widget")

    /// The snapshot of the first book the library would continue.
    static func of(_ library: LibraryModel) -> ReadingSnapshot? {
        let first = library.continueReading.first
        return ReadingSnapshot(publication: first, fractionRead: first.flatMap(library.readFraction(of:)))
    }

    static func publish(_ snapshot: ReadingSnapshot?, library: LibraryModel) async {
        // No container is what a build signed without the App Group gets. There is then no
        // widget that could read the snapshot, so there is nothing to write.
        guard let store = ReadingSnapshotStore.shared() else { return }
        let publication = library.continueReading.first { $0.id == snapshot?.publicationID }
        do {
            let changed = try await store.write(snapshot) {
                guard let publication else { return nil }
                let image = await library.cover(for: publication, maxPixelSize: ReadingSnapshot.coverPixels)
                return image.flatMap(ReadingSnapshotStore.coverJPEG)
            }
            if changed { WidgetCenter.shared.reloadTimelines(ofKind: ReadingSnapshot.widgetKind) }
        } catch {
            // A full disk costs the widget its update, never the app its screen.
            log.error("The widget snapshot was not written: \(error.localizedDescription, privacy: .public)")
        }
    }
}
