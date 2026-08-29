internal import Foundation
internal import SwiftUI

/// Notices when a watched folder's contents change.
///
/// `local-library`: a file added to a watched folder "appears in the library within 10
/// seconds without a manual refresh". The kernel is asked to say so rather than the app
/// polling for it — a poll over ten thousand files would cost more than the change it is
/// looking for.
///
/// One source per *directory*, because a vnode event describes the directory its descriptor
/// was opened on and says nothing about what happened one level down. So the tree is walked
/// once and every directory in it is watched, breadth-first, up to ``limit``: a process has
/// a bounded number of open descriptors, and a library of ten thousand comics in a thousand
/// series would spend them all here. Beyond the limit a change is still noticed on the next
/// return to the foreground, which is the other half of the requirement.
///
/// Android does none of this. `ContentObserver` over the Storage Access Framework already
/// carries descendants, so its watcher is one registration per picked folder. The mechanisms
/// have nothing in common; what mirrors is `FolderSnapshot`, which decides what a change
/// *means*.
@MainActor
final class FolderWatcher {
    /// How many directories are watched at once.
    ///
    /// Well under the process descriptor limit, and far more than a reader's library root
    /// and its series folders.
    static let limit = 96

    private var sources: [String: any DispatchSourceFileSystemObject] = [:]
    private var coalesced: Task<Void, Never>?
    private var notify: (@MainActor () -> Void)?

    /// Watches these folders and everything under them, replacing whatever was watched
    /// before.
    func watch(_ folders: [URL], onChange: @escaping @MainActor () -> Void) {
        stop()
        notify = onChange
        for directory in Self.directories(under: folders) { add(directory) }
    }

    /// Stops watching. Every descriptor is closed by its source's cancel handler.
    func stop() {
        coalesced?.cancel()
        coalesced = nil
        for source in sources.values { source.cancel() }
        sources = [:]
        notify = nil
    }

    deinit {
        for source in sources.values { source.cancel() }
    }

    private func add(_ directory: URL) {
        guard sources[directory.path] == nil else { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler {
            // The source's queue is the main queue, so this is already where the watcher
            // lives; the compiler cannot see that on its own.
            MainActor.assumeIsolated { self.schedule() }
        }
        source.setCancelHandler { close(descriptor) }
        sources[directory.path] = source
        source.resume()
    }

    /// Coalesces a burst into one reconcile.
    ///
    /// Copying a folder of forty comics in produces forty events, and reconciling on each
    /// would walk the tree forty times to notice one arrival at a time. A second's wait is
    /// invisible against the ten the requirement allows.
    private func schedule() {
        coalesced?.cancel()
        coalesced = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.notify?()
        }
    }

    /// Every directory under the watched folders, nearest first, up to ``limit``.
    ///
    /// Breadth-first on purpose: when the limit bites, the folders it keeps are the ones a
    /// reader drops a file into.
    private static func directories(under folders: [URL]) -> [URL] {
        var queue = folders
        var found: [URL] = []
        while !queue.isEmpty, found.count < limit {
            let directory = queue.removeFirst()
            found.append(directory)
            let children = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            queue += children.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
        }
        return found
    }
}

extension View {
    /// Keeps the library in step with folders that change while nobody is looking.
    ///
    /// The watcher covers the app being on screen; this covers the other scenario in
    /// `local-library`, where the change happened while the app was in the background and
    /// no event was delivered to anyone.
    func watchingFolders(of model: LibraryModel) -> some View {
        modifier(WatchingFolders(model: model))
    }
}

private struct WatchingFolders: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let model: LibraryModel

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                // `local-library`: on returning to the foreground the app "reconciles by
                // comparing file modification times and sizes rather than re-reading every
                // archive".
                Task { await model.reconcileWatchedFolders() }
            }
    }
}
