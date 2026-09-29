/// Where a continuous scroll should reopen, and where it leaves off. Split out of
/// `ReaderModel` itself, which is at its line cap.
///
/// `pendingScrollRestore` is read from the store the first time either function here
/// runs, so the first save of this session cannot overwrite what the last one left
/// before the restore has read it. The scroll saves on its very first layout, before
/// it has restored anything.
extension ReaderModel {
    /// The fraction through `page` that the last session's scroll stopped at, handed over
    /// once. `nil` when it stopped on another page, or never stopped at all.
    public func takeScrollRestore(forPage page: Int) -> Double? {
        defer { pendingScrollRestore = nil }
        guard let entry = pendingScrollRestore, entry.page == page else { return nil }
        return entry.fraction
    }

    /// Remembers where a continuous scroll sits within `page`.
    ///
    /// Local only — see `ScrollOffsetMemory` for why this does not touch
    /// `ReadingProgress`, which is what ``record(_:)`` writes and what syncs.
    public func saveScrollFraction(_ fraction: Double, onPage page: Int) {
        guard let preferences else { return }
        _ = pendingScrollRestore
        preferences.save(
            preferences.scrollOffsets().remembering(fraction, onPage: page, for: publication.identity)
        )
    }
}
