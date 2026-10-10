internal import Foundation

internal import StoryArcCore

/// The two things a cover is allowed to say besides how far the reader got.
///
/// `library-browsing` caps a cover at two marks — "how far the reader has got, and whether
/// it can be read with no network" — and forbids a third "for any reason". Both rules here
/// decide the second one from opposite ends: the downloaded mark draws a glyph, and
/// ``awayOpacity`` takes brightness away. Neither ever removes a publication from the shelf,
/// which is the distinction the requirement turns on: "a library that shrinks when the Wi-Fi
/// drops reads as data loss".
///
/// Pure and free of SwiftUI, because a rule asked once per visible cell on every redraw is
/// worth asserting directly rather than reading off a screenshot. Android's `LibraryMarks.kt`
/// is the same file with the same three answers.
///
/// It exists because the two rules had reached exactly one of the app's three shelves. The
/// dim lived in ``SectionedShelf``, whose only call site is gated on a grid of more than
/// twelve items, so a short library and every search result drew unreachable publications at
/// full brightness and ``CoverList`` had neither the dim nor the mark. Rules that live in a
/// layout reach one layout.
enum LibraryMarks {

    /// How dim a publication that cannot be opened right now is drawn.
    ///
    /// One number for the home surface and the library shelf alike. Two of them would be two
    /// answers to "how far down is away", and a reader moving between the two screens would
    /// see the same book at two brightnesses — which is what iOS shipped: 0.45 on the
    /// sectioned shelf against 0.55 on Home. Android has carried one constant since its own
    /// shelf caught up, and this is that constant.
    static let awayOpacity: Double = 0.45

    /// What a cover says out loud, its two marks included.
    ///
    /// Both marks are invisible to VoiceOver — a glyph in a corner and an opacity are not
    /// announcements — and both answer questions a shelf exists to answer: can I read this
    /// with no network, and can I open it at all right now. So the facts belong in the
    /// **label**, which VoiceOver reads first. They rode an `accessibilityHint` before, which
    /// is announced last and, for a reader who has turned hints off, never.
    ///
    /// One function for the grid and the list, so the two layouts cannot answer this
    /// differently — the drift that put the mark on one of them and not the other.
    ///
    /// - Parameters:
    ///   - parts: what the cell itself already says, in reading order. `nil` entries are
    ///     dropped, so a caller may pass an absent subtitle without composing around it.
    ///   - isOnDevice: whether the app's own store holds the bytes.
    ///   - isReadableNow: whether it can be opened at this instant.
    ///   - isFinished: whether the reader has finished it. `library-browsing`'s *The finished
    ///     mark* requires VoiceOver to announce it, because the badge that draws it is a
    ///     glyph in a corner and glyphs are silent.
    static func spoken(
        _ parts: [String?],
        isOnDevice: Bool,
        isReadableNow: Bool,
        isFinished: Bool = false
    ) -> String {
        var spoken = parts.compactMap { $0 }
        if isFinished {
            spoken.append(
                String(localized: "library.cell.finished", bundle: .module, locale: .storyArc)
            )
        }
        // The wording the catalogue already uses for the same state, in the four languages
        // it is already translated into.
        if isOnDevice {
            spoken.append(
                String(localized: "catalogue.entry.downloaded", bundle: .module, locale: .storyArc)
            )
        }
        // Last, as on Android: it is the exception rather than the description, and a reader
        // skimming a shelf hears the title first either way.
        if !isReadableNow {
            spoken.append(
                String(localized: "library.cell.unavailable", bundle: .module, locale: .storyArc)
            )
        }
        return spoken.joined(separator: ", ")
    }

    /// Whether a cover draws the finished badge.
    ///
    /// `library-browsing`'s cap of two marks is not broken by this: the badge *replaces* the
    /// progress rail rather than joining it, the way ``CoverCell/showsOnDeviceMark`` already
    /// substitutes for the pick mark while the reader is selecting. Withheld while picking for
    /// the same reason the on-device mark is — the only question that mode asks is which
    /// covers are picked. A named function rather than the condition inline, so a test can
    /// reach it without a window: Android's `showsFinishedMark` in `LibraryMarks.kt` is the
    /// same rule.
    static func showsFinishedMark(isPicked: Bool?, isFinished: Bool) -> Bool {
        isPicked == nil && isFinished
    }
}

extension LibraryModel {
    /// Whether the shelf draws this publication at full brightness.
    ///
    /// The rule is ``LibraryAvailability/isReadableNow(_:location:registry:)``; this is the
    /// shelf asking it, the way Android's `LibraryViewModel.isReadableNow` asks its own.
    ///
    /// **Not ``isReadableNow(_:)``**, which is Home's question and a different one. Home asks
    /// whether the app can open a file it already holds; the shelf asks whether the library a
    /// publication came from is answering. Two rules, deliberately two names — Android carries
    /// the same pair, one in `LibraryMarks.kt` and one in `HomeDestination.kt`.
    func isReachableNow(_ publication: Publication) -> Bool {
        LibraryAvailability.isReadableNow(
            publication,
            location: location(of: publication),
            registry: registry
        )
    }

    /// Whether the reader has finished this publication.
    ///
    /// `reading-progress` stamps `isFinished` on the record itself rather than leaving a
    /// reader who reached the last page and closed the book without turning it to look
    /// unread forever after — ``readFraction(of:)`` already reads the same field to answer
    /// "1" for it. This is the boolean half of that answer, for the badge rather than the
    /// rail. Android's `LibraryViewModel.isFinished` is the same lookup.
    func isFinished(of publication: Publication) -> Bool {
        progress[publication.id]?.isFinished ?? false
    }

    /// Whether opening this publication carries on from a stored position.
    ///
    /// The title page's primary action says "Continue" only when this is true. A finished
    /// publication reopens at its start (`reading-progress`, *Finished state*), so its action
    /// says "Read" or "Listen". Task 26.5: the walks saw "Continue reading" open a finished
    /// comic on its first page.
    func continuesInPlace(_ publication: Publication) -> Bool {
        !isFinished(of: publication) && (readFraction(of: publication) ?? 0) > 0
    }
}
