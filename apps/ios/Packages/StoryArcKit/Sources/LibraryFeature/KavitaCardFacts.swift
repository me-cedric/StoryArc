import SwiftUI

internal import DesignSystem
import Kavita
import StoryArcCore

/// The two things a Kavita download says about itself that no file on this device can.
///
/// `kavita-server`: "when a downloaded Kavita publication is opened with the server
/// unreachable, the cached server metadata is displayed, not the file's embedded metadata".
/// Five of the seven fields that requirement names — a summary, genres, tags, people and a
/// release year — reach the page through ``KavitaCard/applied(to:)``, which lays the card
/// over the publication indexed from the file, because ``Publication`` has somewhere to put
/// each of them. The publication status and the age rating are the other two: there is no
/// slot for either and no local file states them, so they stay on the card and are read from
/// it here.
///
/// A named line each rather than a run of facts, which is the same decision
/// ``KavitaChapterList`` makes for the live answer and for the same reason: a rating dropped
/// unlabelled into "2020 · Ada Lovelace · Drama · Teen" is a rating a reader would take for a
/// genre, and this is the one field where being mistaken for something else matters.
///
/// **Nothing at all when there is nothing to say**, which is most of the shelf: no card, or a
/// card that recorded neither number. Not an empty block — the page stacks this at
/// ``StoryArcSpace/xl``, so a view that returned a zero-height layout node would still leave
/// 24 pt of nothing under the description of every publication that never came from Kavita.
/// ``KavitaCardFactsTests`` measures that.
///
/// The card is passed in rather than read here. ``PublicationDetailView`` reads it once, in
/// the task it already runs per publication, which is what lets this view resolve to nothing
/// at all: a view that owned the read would have to exist in order to perform it.
///
/// Android's `KavitaCardFacts` draws the same two lines from the same card, and returns
/// before composing anything for the same reason.
struct KavitaCardFacts: View {
    @Environment(\.theme) private var theme

    /// What the server said when the chapter was kept, or `nil` for a publication that was
    /// never kept from a Kavita server.
    let card: KavitaCard?

    /// Whether the card says either of the two things, which is what decides that the block
    /// exists at all. A card is not enough: one written before these fields existed, or kept
    /// from a server that stated neither, has nothing to draw.
    private var isStating: Bool { card?.status != nil || card?.rating != nil }

    var body: some View {
        if isStating {
            VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
                if let status = card?.status {
                    Text("kavita.status \(status.name)", bundle: .module)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textSecondary)
                }
                // Absent unless the server actually stated one. `KavitaCard.rating` drops
                // Kavita's `Unknown` and `Not Applicable`, because a line saying a book had
                // been rated when nobody rated it is worse than no line.
                if let rating = card?.rating {
                    // The rating's own label, unchanged: ComicInfo.xml v2.1's vocabulary,
                    // which is where Kavita takes it from. See ``KavitaAgeRating/label``.
                    Text("kavita.ageRating \(rating.label)", bundle: .module)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension KavitaPublicationStatus {
    /// What this app calls each of Kavita's five states, in the reader's own language.
    ///
    /// **Five literal keys rather than a table of `String.LocalizationValue`.**
    /// `scripts/ios-strings.mjs` finds the keys a screen asks for by matching literals at a
    /// `Text(` or `String(localized:` call site; a key handed over as a value is invisible to
    /// it, so a typo would render `kavita.status.hiatus` on the screen with nothing failing
    /// — and the host test suite cannot resolve a string catalogue at all, because
    /// `swift test` does not compile `.xcstrings`. Written this way the gate sees all five,
    /// and a missing translation in any of the four languages fails `pnpm lint`.
    var name: String {
        switch self {
        case .ongoing: String(localized: "kavita.status.ongoing", bundle: .module, locale: .storyArc)
        case .hiatus: String(localized: "kavita.status.hiatus", bundle: .module, locale: .storyArc)
        case .completed:
            String(localized: "kavita.status.completed", bundle: .module, locale: .storyArc)
        case .cancelled:
            String(localized: "kavita.status.cancelled", bundle: .module, locale: .storyArc)
        case .ended: String(localized: "kavita.status.ended", bundle: .module, locale: .storyArc)
        }
    }
}
