public import StoryArcCore

/// The two fields of ``KavitaMetadata`` that arrive as bare integers.
///
/// Everything else the server sends about a series is already legible — a summary is a
/// sentence, a genre is a word, a year is a year. `ageRating` and `publicationStatus` are
/// positions in a C# enum, and a screen that printed `10` would be displaying a number rather
/// than the metadata `kavita-server`'s *Metadata* requirement names.
///
/// **The numbers are Kavita's, and they are copied from Kavita rather than guessed.**
/// `Kavita.Models/Entities/Enums/AgeRating.cs` and `PublicationStatus.cs` in
/// `Kareadita/Kavita` are the source, read on 2026-08-31; the age rating's own comment there
/// records that its values come from ComicInfo.xml v2.1. Getting one wrong is not a cosmetic
/// bug — the age rating is parental-control adjacent, and an off-by-one would show a reader
/// *Teen* where the server said *Mature 17+*.
///
/// A value that is not in the table is `nil` rather than a guess. Kavita adds cases (v2.1
/// added several to the rating), and an app that mapped an unknown number onto the nearest one
/// it knew would state a rating no server ever gave.
///
/// The Android mirror is `core/kavita/KavitaRatings.kt`, and the tables must agree. They are
/// the same list read from the same file on the same day; if one is ever edited alone, the two
/// apps will disagree about a parental control.
public enum KavitaAgeRating: Int, Sendable, CaseIterable {
    /// Kavita's own value for a restricted profile, not a rating a series carries.
    case notApplicable = -1
    case unknown = 0
    case ratingPending = 1
    case earlyChildhood = 2
    case everyone = 3
    case ratedG = 4
    case everyone10Plus = 5
    case pg = 6
    case kidsToAdults = 7
    case teen = 8
    case mature15Plus = 9
    case mature17Plus = 10
    case mature = 11
    case r18Plus = 12
    case adultsOnly = 13
    case x18Plus = 14

    /// What the rating scheme calls itself.
    ///
    /// **Not translated, deliberately.** It is an issued mark from ComicInfo.xml v2.1's own
    /// vocabulary — which is where Kavita takes it from — and half of them are codes nobody
    /// would translate anyway (`G`, `PG`, `MA15+`, `R18+`, `X18+`). A paraphrased rating is a
    /// rating no body ever gave, which is the one thing a parental-control line must not say.
    /// Only the word introducing it is the app's, so only that is localised.
    public var label: String {
        switch self {
        case .notApplicable: "Not Applicable"
        case .unknown: "Unknown"
        case .ratingPending: "Rating Pending"
        case .earlyChildhood: "Early Childhood"
        case .everyone: "Everyone"
        case .ratedG: "G"
        case .everyone10Plus: "Everyone 10+"
        case .pg: "PG"
        case .kidsToAdults: "Kids to Adults"
        case .teen: "Teen"
        case .mature15Plus: "MA15+"
        case .mature17Plus: "Mature 17+"
        case .mature: "M"
        case .r18Plus: "R18+"
        case .adultsOnly: "Adults Only 18+"
        case .x18Plus: "X18+"
        }
    }

    /// Whether the server actually stated a rating.
    ///
    /// `unknown` is Kavita's default for a series nobody has rated and `notApplicable` is a
    /// profile setting that leaked into the same enum. Neither is a rating, and drawing either
    /// would tell a parent this book had been assessed when it has not — which is the one
    /// mistake a rating line must not make.
    public var isStated: Bool { self != .unknown && self != .notApplicable }
}

/// Where a series is in its own life, as Kavita records it.
///
/// Unlike the age rating there is no "unknown" here: Kavita's default is `OnGoing` and every
/// one of the five is a real state a curator chose or accepted. So the line is drawn whenever
/// the number is one this app knows, and omitted only when it is not.
///
/// `library-browsing` records why this cannot be a filter over the whole library — no local
/// file states it, so filtering on it would narrow a folder's shelf to nothing. Showing what
/// one server said about one of its own series is the other thing entirely, and it is what
/// `kavita-server`'s *Metadata* requirement asks for.
public enum KavitaPublicationStatus: Int, Sendable, CaseIterable {
    case ongoing = 0
    case hiatus = 1
    case completed = 2
    case cancelled = 3

    /// Kavita's own distinction: finished releasing, but the server lacks every issue.
    case ended = 4
}

extension KavitaMetadata {
    /// The rating this metadata states, or `nil` when it states none.
    ///
    /// On the model rather than inside the screen, so the two rules a rating line turns on —
    /// an unrecognised number is not a rating, and Kavita's two non-ratings are not ratings —
    /// are decided once and asserted without drawing anything.
    public var rating: KavitaAgeRating? {
        KavitaAgeRating(rawValue: ageRating).flatMap { $0.isStated ? $0 : nil }
    }

    /// The state this metadata puts the series in, or `nil` when the number is unrecognised.
    public var status: KavitaPublicationStatus? {
        KavitaPublicationStatus(rawValue: publicationStatus)
    }
}

extension KavitaCard {
    /// The rating the card kept, or `nil` when it kept none.
    ///
    /// The same two rules as ``KavitaMetadata/rating``, applied to what was written down.
    /// That is the whole shape of *Reading a downloaded Kavita title offline*: the offline
    /// path is the live path with the card in place of the response.
    public var rating: KavitaAgeRating? {
        guard let stated = KavitaAgeRating.of(ageRating), stated.isStated else { return nil }
        return stated
    }

    /// The state the card kept, or `nil` when it kept none.
    ///
    /// Nil covers two things and has to: a number Kavita has never defined, and the -1
    /// ``KavitaCard/publicationStatus`` carries for a card written before the field existed.
    /// Zero is *OnGoing*, so a card that fell back to it would state that the series is
    /// running on a server's behalf.
    public var status: KavitaPublicationStatus? {
        KavitaPublicationStatus.of(publicationStatus)
    }
}
