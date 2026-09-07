internal import Foundation
internal import SwiftUI

internal import StoryArcCore

/// What the publication page's one primary action says.
///
/// `publication-detail` makes the wording an accessibility requirement rather than a
/// preference: one thing the screen wants you to do, "labelled with *which* of read and
/// continue will happen — so a screen-reader user learns the outcome before taking it rather
/// than after".
///
/// **Four answers, not two, and the missing pair was a real defect.** An audiobook's button
/// said *Read*. It never opened a reader — `StoryArcApp.open(_:at:)` has asked
/// `format.isAudio` since audiobooks landed and sends one to the player — so the routing was
/// right and only the promise was wrong, which is the kind of wrong nothing fails on.
///
/// A value with a test rather than a ternary in a view body, for the reason `PlayerLabels` is
/// one: a requirement stated inside a `Text` is a requirement nothing checks.
enum PrimaryAction: Hashable, Sendable {
    case read
    case continueReading
    case listen
    case continueListening
    /// *Continue*, naming the chapter it will resume inside.
    ///
    /// `audio-playback`, "Chapters before the first minute": the action "names the chapter it
    /// will resume inside", and "an audiobook never started offers to start it, naming no
    /// chapter". A fifth case rather than a payload on ``continueListening``, because the two
    /// are different promises and a screen reader hears the difference.
    case resumeChapter(ChapterName)

    /// - Parameters:
    ///   - hasProgress: whether the reader has a recorded position above zero.
    ///   - chapter: the chapter the recorded position falls inside, when the page knows it.
    ///     `nil` for a book never started, for one whose parts the device cannot read, and for
    ///     the single unnamed part of a single-part book — see
    ///     ``DetailChapters/of(_:parts:progress:)``.
    ///
    /// It asks `format.isAudio` rather than listing the audio formats, so a format added later
    /// cannot miss this branch — the same rule, for the same reason, as the routing in
    /// `StoryArcApp.open(_:at:)`.
    static func of(
        _ format: PublicationFormat,
        hasProgress: Bool,
        chapter: ChapterName? = nil
    ) -> PrimaryAction {
        switch (format.isAudio, hasProgress) {
        case (true, false): .listen
        case (true, true): chapter.map(PrimaryAction.resumeChapter) ?? .continueListening
        case (false, false): .read
        case (false, true): .continueReading
        }
    }

    /// The words. Each key is a literal in this file so `scripts/ios-strings.mjs` can see it.
    var label: Text {
        switch self {
        case .read: Text("catalogue.detail.read", bundle: .module)
        case .continueReading: Text("library.continueReading", bundle: .module)
        case .listen: Text("detail.listen", bundle: .module)
        case .continueListening: Text("detail.continueListening", bundle: .module)
        case let .resumeChapter(name):
            Text("detail.continueListening.in \(Self.spelling(of: name))", bundle: .module)
        }
    }

    /// A chapter's name as one string, so the sentence around it stays one key.
    ///
    /// The number is resolved here rather than composed by the caller, by
    /// ``PlayerCentre``'s own rule and against ``StoryArcCore/Locale/storyArc``: a part
    /// numbered in the device's language inside a sentence in the reader's chosen one is the
    /// defect this locale exists to prevent.
    private static func spelling(of name: ChapterName) -> String {
        switch name {
        case let .given(title): title
        case let .numbered(number):
            String(localized: "detail.chapter.number \(number)", bundle: .module, locale: .storyArc)
        }
    }
}
