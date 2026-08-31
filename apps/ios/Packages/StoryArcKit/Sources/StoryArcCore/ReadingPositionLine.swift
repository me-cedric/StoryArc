/// Where a reader is in a reflowable publication, said in one line.
///
/// `ebook-reader`, *Progress display*:
///
/// > **THEN** one line states how far through the publication they are and how much of the
/// > current chapter is left, in words
/// > **AND** because reflowable page counts depend on typography, the app never presents a
/// > reflowable page number as a stable identity
/// > **AND** no slider is offered, and the position is not drawn over the page
///
/// **This type has no page number in it, and that is the point.** *A publication that
/// declares no chapters* requires the line to state progress alone and to not "fall back to
/// a page count, because that is the identity the app refuses to present". A rule enforced
/// by a branch can be undone by an `else`; a rule enforced by the absence of a field cannot
/// be undone without changing the type both readers share.
///
/// A rule rather than a rendering detail, which is why it lives here and not in either
/// reader: both need it, and a reader that says one thing on one platform and another on the
/// other is exactly the divergence this module exists to prevent. ``TotalProgression`` — the
/// input to this — lives here for the same reason. Android mirrors it in `:core:model`.
public struct ReadingPositionLine: Equatable, Sendable {
    /// How far through the whole publication, as a percentage a reader can read aloud.
    public let percentThrough: Int

    /// The chapter the reader is in, or `nil` where the publication declares no navigation.
    public let chapter: String?

    /// Roughly how much of that chapter is left, or `nil` where there is no chapter to
    /// measure or the renderer could not say where in it the reader is.
    public let chapterRemainder: ChapterRemainder?

    public init(percentThrough: Int, chapter: String?, chapterRemainder: ChapterRemainder?) {
        self.percentThrough = percentThrough
        self.chapter = chapter
        self.chapterRemainder = chapterRemainder
    }

    /// Builds the line from what the renderer knows.
    ///
    /// - Parameters:
    ///   - totalProgression: how far through the whole publication, 0…1. See
    ///     ``TotalProgression`` for why the renderer's own answer is not trusted blindly.
    ///   - chapter: the current chapter's title. Blank and `nil` are the same thing: a
    ///     publication with no navigation, and Readium reports both.
    ///   - withinChapter: how far through the current resource, 0…1, or `nil` when the
    ///     renderer has not said.
    public static func of(
        totalProgression: Double,
        chapter: String?,
        withinChapter: Double?
    ) -> ReadingPositionLine {
        let clamped = min(max(totalProgression, 0), 1)
        let percent = Int((clamped * 100).rounded())

        let named = chapter?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let named, !named.isEmpty else {
            // No chapter, and therefore nothing to say about a chapter. Not a page count:
            // `ebook-reader` names that fallback and forbids it.
            return ReadingPositionLine(percentThrough: percent, chapter: nil, chapterRemainder: nil)
        }

        return ReadingPositionLine(
            percentThrough: percent,
            chapter: named,
            chapterRemainder: withinChapter.map(ChapterRemainder.of)
        )
    }
}

/// How much of the current chapter is left, coarsely, in words.
///
/// **Why words and not a second percentage.** The requirement says "how much of the current
/// chapter is left, in words", and a line reading *42% through · Chapter Three, 63% left* is
/// two numbers a reader has to hold at once to learn one thing. The coarse band is what a
/// reader actually wants from a chapter — whether to keep going before putting the book down
/// — and it is all a within-chapter percentage is accurate enough to say anyway: the
/// renderer's within-resource progression moves in jumps the width of a screen.
///
/// Five bands rather than three: *nearly done* and *just begun* are the two a reader acts on,
/// and collapsing them into *less than half* and *more than half* loses exactly the decision
/// the line is there to inform.
public enum ChapterRemainder: String, CaseIterable, Sendable {
    case nearlyDone
    case lessThanHalfLeft
    case aboutHalfLeft
    case moreThanHalfLeft
    case justBegun

    /// The band a within-chapter progression falls in.
    ///
    /// Measured on what is *left*, not on what is read: the line says how much is left, and
    /// a threshold table written against the other quantity is one inversion away from
    /// saying the opposite.
    ///
    /// The bands, by how much is left: under a tenth is nearly done, under two fifths is
    /// less than half, up to three fifths is about half, under nine tenths is more than
    /// half, and the rest is just begun. Each boundary belongs to the band below it.
    public static func of(withinChapter: Double) -> ChapterRemainder {
        let left = 1 - min(max(withinChapter, 0), 1)
        if left < 0.1 { return .nearlyDone }
        if left < 0.4 { return .lessThanHalfLeft }
        if left <= 0.6 { return .aboutHalfLeft }
        if left < 0.9 { return .moreThanHalfLeft }
        return .justBegun
    }

    /// The string key naming this band, resolved in each feature module's own catalogue.
    ///
    /// The key rather than a `LocalizedStringKey`: this target has no string catalogue and
    /// should not gain one for five phrases.
    public var titleKey: String { "reader.chapter.left.\(rawValue)" }
}
