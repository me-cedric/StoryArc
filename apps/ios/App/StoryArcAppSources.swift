import Formats
import LibraryFeature
import Persistence
import Playback
import PlayerFeature
import ReaderFeature
import Smb
import StoryArcCore
import SwiftUI

/// The five things a source's detail screen offers, resolved against the app's own stores.
///
/// `sources` names them all: test the connection, refresh, clear the cache, remove
/// downloads, remove the source. The first three are the library's; the last two also touch
/// the download store, which the scene owns rather than the library — so this is where the
/// two halves meet. Android's `MainActivity` carries the same switch.
///
/// Split out of `StoryArcAppActions.swift`, which had reached the 400-line cap this project
/// enforces — this is a seam of its own, source management rather than opening or reading a
/// publication.
extension StoryArcApp {
    func perform(_ action: SourceAction, on source: Source) async {
        switch action {
        // The sheet the source was added through, re-opened with everything but the secret.
        // Presented from here rather than run here, because the answer arrives when the
        // reader has finished typing.
        case .reconnect: reconnecting = source
        case .testConnection: await library.test(source)
        case .refresh: await library.refresh(source)
        case .clearCache: library.clearCache(of: source)
        case .removeDownloads: removeDownloads(of: source)
        case .remove: removeSource(source)
        }
    }

    /// Removes a source, and everything `sources` says goes with it.
    ///
    /// The downloads first. The registry entry is what attributes a download to a source, so
    /// deleting the source before its files leaves bytes on disk that nothing in the app can
    /// name, let alone offer to remove.
    func removeSource(_ source: Source) {
        removeDownloads(of: source)
        library.remove(source, credentials: credentials, pins: .app)
    }

    /// Deletes the files one source produced, and the records of them.
    ///
    /// The source itself stays. `sources` lists this as its own action beside removal, and a
    /// reader freeing space before a flight has not asked to disconnect their server.
    ///
    /// Through the shared queue rather than a plain `downloadStore.save` — `offline-downloads`
    /// 1.1: that write used to compete with whichever catalogue queue saved next, which is
    /// exactly what "a source removal is undone by the next queue save" describes.
    func removeDownloads(of source: Source) {
        let removed = DownloadQueue.shared().removingAll(from: source.id)
        guard !removed.isEmpty else { return }
        downloads = DownloadQueue.shared().library
        // What a Kavita server said about those downloads goes with them. A card left behind
        // describes bytes nobody has: it corrupts nothing, and it would put a row in an
        // offline search that opens nothing.
        KavitaCardStore().removeAll(from: source.id.uuidString)
    }
}
