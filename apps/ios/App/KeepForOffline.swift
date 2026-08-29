import Foundation

import Formats

/// Copies a publication off a share and onto the device.
///
/// `network-share`: when reconnection has failed for a minute "the app offers to download
/// the current publication for offline reading". This is that offer carried out — the bytes
/// are fetched once and the reader reopens from the copy, so the rest of the session no
/// longer depends on the network.
///
/// Returns where the copy landed, or `nil` when the share is still unreachable, which is
/// the likeliest outcome and not a surprise: the offer exists because the network is down.
///
/// A file of its own, beside Android's `KeepForOffline.kt`, because `StoryArcApp` is at its
/// line cap and this is a whole job rather than a step of one.
///
/// - Parameter directory: where the copy goes, which is the download store's own. Passed as
///   a path rather than as the store, so nothing main-actor-isolated crosses into here.
func keptForOffline(_ remote: URL, into directory: URL) async -> URL? {
    guard let source = try? await ComicArchiveOpener.source(for: remote),
          let bytes = try? await source.read(offset: 0, count: Int(source.length))
    else { return nil }

    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appending(path: remote.lastPathComponent)
    guard (try? bytes.write(to: file, options: .atomic)) != nil else { return nil }
    return file
}
