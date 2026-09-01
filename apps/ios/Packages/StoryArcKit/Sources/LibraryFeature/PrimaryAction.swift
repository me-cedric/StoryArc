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
enum PrimaryAction: Equatable, Sendable {
    case read
    case continueReading
    case listen
    case continueListening

    /// - Parameter hasProgress: whether the reader has a recorded position above zero.
    ///
    /// It asks `format.isAudio` rather than listing the audio formats, so a format added later
    /// cannot miss this branch — the same rule, for the same reason, as the routing in
    /// `StoryArcApp.open(_:at:)`.
    static func of(_ format: PublicationFormat, hasProgress: Bool) -> PrimaryAction {
        switch (format.isAudio, hasProgress) {
        case (true, false): .listen
        case (true, true): .continueListening
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
        }
    }
}
