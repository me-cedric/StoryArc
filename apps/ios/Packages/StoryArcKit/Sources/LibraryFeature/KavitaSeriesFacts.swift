internal import SwiftUI

internal import DesignSystem
internal import Kavita

/// What a Kavita series says about itself, above its volumes.
///
/// Split out of `KavitaChapterList`, which reached the 400-line cap this project enforces when
/// the status and the age rating landed in it. The division is the one the file already made:
/// the list is volumes and chapters, and this is the series.
///
/// `kavita-server`'s *Metadata* requirement names seven things the app SHALL display — summary,
/// genres, tags, people, publication status, age rating, and release year — and the last two
/// arrive as bare integers, so they were decoded by nothing and drawn nowhere on this platform.
/// Android had decoded them and drew them; iOS did neither, which is what
/// `docs/delivery/remaining-work-2026-08-31.md` ranks as gap 14.
struct KavitaSeriesFacts: View {
    @Environment(\.theme) private var theme

    let metadata: KavitaMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            if let summary = metadata.summary, !summary.isEmpty {
                Text(summary)
                    .textRole(.body)
                    .foregroundStyle(theme.palette.textPrimary)
            }

            // A year, a writer and a genre are all facts *about* the book and read as one
            // line; the two below are statements about it that carry a word of their own,
            // which a middle dot cannot supply.
            if !metadata.facts.isEmpty {
                Text(metadata.facts.joined(separator: " · "))
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
            }

            // Neither line appears for a number this app does not recognise, and the rating
            // additionally does not appear for Kavita's two non-ratings, `Unknown` and `Not
            // Applicable` — drawing either would tell a parent this book had been assessed
            // when nobody has assessed it. ``KavitaAgeRating`` and ``KavitaPublicationStatus``
            // own both rules and are tested without drawing anything.
            if let status = metadata.status {
                Text("kavita.status \(statusName(status))", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            if let rating = metadata.rating {
                Text("kavita.ageRating \(rating.label)", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
    }

    /// What this app calls each of Kavita's five states, in the reader's own language.
    ///
    /// The status is the app's word for a state. The age rating is not: it is an issued mark
    /// from ComicInfo.xml v2.1's own vocabulary and this app must not paraphrase it — see
    /// ``KavitaAgeRating/label``. So one of the two lines is translated and the other is not,
    /// and only the word introducing the rating belongs to the app.
    private func statusName(_ status: KavitaPublicationStatus) -> String {
        let key: String.LocalizationValue = switch status {
        case .ongoing: "kavita.status.ongoing"
        case .hiatus: "kavita.status.hiatus"
        case .completed: "kavita.status.completed"
        case .cancelled: "kavita.status.cancelled"
        case .ended: "kavita.status.ended"
        }
        return String(localized: key, bundle: .module, locale: .storyArc)
    }
}
