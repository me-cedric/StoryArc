/// Whether the first few decoded pages of a publication read as a webtoon.
///
/// `comic-reader` recognises a webtoon by pages "materially taller than they are
/// wide", measured from early pages rather than declared, because a webtoon rarely
/// says it is one and waiting for the tallest page of the whole run means waiting
/// for the whole publication.
///
/// **More than one page**, because the first alone is not enough: a webtoon chapter
/// often opens on a short title image, and a rule that stopped at page one read that
/// as ordinary panels and defaulted Scroll to horizontal. A struct of its own, held
/// outside `ReaderModel`, so `EarlyPageTallnessTests` can drive it with plain numbers
/// — `ReaderModel` needs a real decoded `CGImage` for each page, which is not
/// something a host-run test can make three of cheaply.
struct EarlyPageTallness {
    /// How many of the earliest pages count. Three catches a one-page title card
    /// without waiting long enough to matter for anything longer.
    static let sampleCount = 3

    private(set) var tallestRatio = 0.0

    /// Notes one decoded page's height-over-width ratio, if it is early enough to count.
    mutating func note(ratio: Double, at index: Int) {
        guard index < Self.sampleCount else { return }
        tallestRatio = max(tallestRatio, ratio)
    }
}
