internal import Foundation

/// Whether the shelf as it now stands is worth writing over the one already on disk.
///
/// Two refusals, and both are about not making a reader's next launch worse than their
/// last.
///
/// **A partial walk has refreshed nothing.** The notice says "cached, refreshed at X", and
/// that moment used to be written the instant any walk finished — including a walk that saw
/// nothing because it could see nothing, which is exactly when a reader most needs to be
/// told the shelf is last session's. `sources` asks the indicator to state when the content
/// was last refreshed; writing `now` for a walk that could not list a directory puts that
/// lie on disk for the next launch as well.
///
/// **An empty shelf must not replace a full snapshot.** One unreadable folder, or one
/// server that did not answer, would otherwise cost the reader their whole cached library
/// on the next launch too.
///
/// Pure, so both refusals can be asserted without a cache directory. ``LibrarySnapshotTests``
/// is that assertion; Android's `LibrarySnapshot` is the twin.
enum LibrarySnapshot {

    /// - Parameters:
    ///   - partial: whether the walk that produced `shelf` met something it could not read.
    ///   - shelf: how many publications are on the shelf now.
    ///   - cached: how many the snapshot on disk holds.
    static func worthWriting(partial: Bool, shelf: Int, cached: Int) -> Bool {
        !partial && !(shelf == 0 && cached > 0)
    }
}
