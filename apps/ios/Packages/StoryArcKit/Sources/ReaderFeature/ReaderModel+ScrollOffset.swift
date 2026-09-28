/// Where a continuous scroll should reopen, and where it leaves off. Split out of
/// `ReaderModel` itself, which is at its line cap.
extension ReaderModel {
    /// The fraction through `currentPage` a continuous scroll last stopped at, or 0
    /// when none was ever stored — which reopens at the page's own top, exactly as
    /// today.
    public var restoredScrollFraction: Double {
        preferences?.scrollOffsets().fraction(for: publication.identity) ?? 0
    }

    /// Remembers where a continuous scroll sits within the current page.
    ///
    /// Local only — see `ScrollOffsetMemory` for why this does not touch
    /// `ReadingProgress`, which is what ``record(_:)`` writes and what syncs.
    public func saveScrollFraction(_ fraction: Double) {
        guard let preferences else { return }
        preferences.save(preferences.scrollOffsets().remembering(fraction, for: publication.identity))
    }
}
