package app.storyarc.core.kavita

import app.storyarc.core.model.KavitaCard

/**
 * The two fields of [KavitaMetadata] that arrive as bare integers.
 *
 * Everything else the server sends about a series is already legible — a summary is a
 * sentence, a genre is a word, a year is a year. `ageRating` and `publicationStatus` are
 * positions in a C# enum, and a screen that printed `10` would be displaying a number rather
 * than the metadata `kavita-server`'s *Metadata* requirement names.
 *
 * **The numbers are Kavita's, and they are copied from Kavita rather than guessed.**
 * `Kavita.Models/Entities/Enums/AgeRating.cs` and `PublicationStatus.cs` in
 * `Kareadita/Kavita` are the source, read on 2026-08-31; the age rating's own comment there
 * records that its values come from ComicInfo.xml v2.1. Getting one wrong is not a cosmetic
 * bug — the age rating is parental-control adjacent, and an off-by-one would show a reader
 * *Teen* where the server said *Mature 17+*.
 *
 * A value that is not in the table is `null` rather than a guess, on both. Kavita adds cases
 * (v2.1 added several to the rating), and an app that mapped an unknown number onto the
 * nearest one it knew would state a rating no server ever gave.
 */
enum class KavitaAgeRating(val number: Int, val label: String) {
    /** Kavita's own value for a restricted profile, not a rating a series carries. */
    NOT_APPLICABLE(-1, "Not Applicable"),
    UNKNOWN(0, "Unknown"),
    RATING_PENDING(1, "Rating Pending"),
    EARLY_CHILDHOOD(2, "Early Childhood"),
    EVERYONE(3, "Everyone"),
    G(4, "G"),
    EVERYONE_10_PLUS(5, "Everyone 10+"),
    PG(6, "PG"),
    KIDS_TO_ADULTS(7, "Kids to Adults"),
    TEEN(8, "Teen"),
    MATURE_15_PLUS(9, "MA15+"),
    MATURE_17_PLUS(10, "Mature 17+"),
    MATURE(11, "M"),
    R18_PLUS(12, "R18+"),
    ADULTS_ONLY(13, "Adults Only 18+"),
    X18_PLUS(14, "X18+"),
    ;

    /**
     * Whether the server actually stated a rating.
     *
     * `Unknown` is Kavita's default for a series nobody has rated and `Not Applicable` is a
     * profile setting that leaked into the same enum. Neither is a rating, and drawing
     * either would tell a parent this book had been assessed when it has not — which is the
     * one mistake a rating line must not make.
     */
    val isStated: Boolean get() = this != UNKNOWN && this != NOT_APPLICABLE

    companion object {
        /** The rating the server sent, or `null` for a number this app has never heard of. */
        fun of(number: Int): KavitaAgeRating? = entries.firstOrNull { it.number == number }
    }
}

/**
 * Where a series is in its own life, as Kavita records it.
 *
 * Unlike the age rating there is no "unknown" here: Kavita's default is `OnGoing` and every
 * one of the five is a real state a curator chose or accepted. So the line is drawn whenever
 * the number is one this app knows, and omitted only when it is not.
 *
 * `library-browsing` records why this cannot be a filter over the whole library — no local
 * file states it, so filtering on it would narrow a folder's shelf to nothing. Showing what
 * one server said about one of its own series is the other thing entirely, and it is what
 * `kavita-server`'s *Metadata* requirement asks for.
 */
enum class KavitaPublicationStatus(val number: Int) {
    ONGOING(0),
    HIATUS(1),
    COMPLETED(2),
    CANCELLED(3),

    /** Kavita's own distinction: finished releasing, but the server lacks every issue. */
    ENDED(4),
    ;

    companion object {
        /** The status the server sent, or `null` for a number this app has never heard of. */
        fun of(number: Int): KavitaPublicationStatus? = entries.firstOrNull { it.number == number }
    }
}

/**
 * The rating this metadata states, or `null` when it states none.
 *
 * On [KavitaMetadata] rather than inside the screen, so the two rules a rating line turns on
 * — an unrecognised number is not a rating, and Kavita's two non-ratings are not ratings —
 * are decided once and asserted without drawing anything.
 */
val KavitaMetadata.rating: KavitaAgeRating?
    get() = KavitaAgeRating.of(ageRating)?.takeIf { it.isStated }

/** The state this metadata puts the series in, or `null` when the number is unrecognised. */
val KavitaMetadata.status: KavitaPublicationStatus?
    get() = KavitaPublicationStatus.of(publicationStatus)

/**
 * The rating the card kept, or `null` when it kept none.
 *
 * The same two rules as [KavitaMetadata.rating], applied to what was written down. That is
 * the whole shape of *Reading a downloaded Kavita title offline*: the offline path is the
 * live path with the card in place of the response.
 */
val KavitaCard.rating: KavitaAgeRating?
    get() = KavitaAgeRating.of(ageRating)?.takeIf { it.isStated }

/**
 * The state the card kept, or `null` when it kept none.
 *
 * Null covers two things and has to: a number Kavita has never defined, and the -1
 * [KavitaCard.publicationStatus] carries for a card written before the field existed. Zero
 * is *OnGoing*, so a card that fell back to it would state that the series is running on a
 * server's behalf.
 */
val KavitaCard.status: KavitaPublicationStatus?
    get() = KavitaPublicationStatus.of(publicationStatus)
