import SwiftUI

internal import DesignSystem
import Kavita
import Persistence
import StoryArcCore

/// The two things a Kavita download says about itself that no file on this device can.
///
/// `kavita-server`: "when a downloaded Kavita publication is opened with the server
/// unreachable, the cached server metadata is displayed, not the file's embedded metadata".
/// Five of the seven fields that requirement names reach the page through
/// ``KavitaCard/applied(to:)``, which lays the card over the publication indexed from the
/// file — a title, a series, people, a year and a summary all have somewhere to go. The
/// publication status and the age rating do not: ``Publication`` has no slot for either, and
/// no local file states them, so they stay on the card and are read from it here.
///
/// A named line each rather than a run of facts, which is the same decision
/// ``KavitaChapterList`` makes for the live answer and for the same reason: a rating dropped
/// unlabelled into "2020 · Ada Lovelace · Drama · Teen" is a rating a reader would take for a
/// genre, and this is the one field where being mistaken for something else matters.
///
/// Absent for every publication that is not a kept Kavita chapter, which is most of them:
/// there is no card, so there is nothing to draw and no empty block left behind.
///
/// Android's `KavitaCardFacts` draws the same two lines from the same card.
struct KavitaCardFacts: View {
    @Environment(\.theme) private var theme

    let publicationId: String

    /// Read once per publication rather than on every redraw. The card is written when the
    /// chapter is kept and never changes afterwards, so a redraw has nothing to learn.
    @State private var card: KavitaCard?

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            if let status = card?.status {
                Text("kavita.status \(status.name)", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            // Absent unless the server actually stated one. `KavitaCard.rating` drops
            // Kavita's `Unknown` and `Not Applicable`, because a line saying a book had been
            // rated when nobody rated it is worse than no line.
            if let rating = card?.rating {
                // The rating's own label, unchanged: ComicInfo.xml v2.1's vocabulary, which
                // is where Kavita takes it from. See the note on ``KavitaAgeRating/label``.
                Text("kavita.ageRating \(rating.label)", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: publicationId) {
            card = KavitaCardStore().card(of: publicationId)
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
