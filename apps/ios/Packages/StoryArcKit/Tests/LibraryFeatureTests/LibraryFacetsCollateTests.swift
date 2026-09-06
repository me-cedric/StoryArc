import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The filter menu files its values where the reader's language files them.
///
/// The shelf, the search results and a reading list all collate in the reader's language. The
/// menu that narrows them did not: it sorted with a bare `sorted()`, which is Swift's `<` on
/// `String` and therefore code point order. Every accented value landed after every unaccented
/// one, so a French reader looking for *Éditions du Lombard* found it after *Zenith Press* —
/// past the end of the alphabet, in a list the reader reads as an alphabet.
///
/// Code point order is not the wrong collation. It is no collation at all, which is why the
/// defect is the same in all four languages StoryArc ships rather than only in some.
///
/// Android's `LibraryFacetsCollateTest` holds the same two names and the same expectation
/// (ADR-0001).
@MainActor
@Suite("The filter menu collates in the reader's language", .serialized)
struct LibraryFacetsCollateTests {

    /// Two values whose order the alphabet and the code point table disagree about.
    ///
    /// *É* is U+00C9 and *Z* is U+005A, so every code point comparison puts *Zenith* first. No
    /// language StoryArc ships agrees: all four file *É* with *E*.
    private static let accented = "Éditions du Lombard"
    private static let plain = "Zenith Press"

    private static let library: [Publication] = [
        publication(publisher: accented, genre: "Épouvante", tag: "épisodique", language: "fr"),
        publication(publisher: plain, genre: "Zombies", tag: "zines", language: "zu"),
    ]

    private static func publication(
        publisher: String,
        genre: String,
        tag: String,
        language: String
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/\(publisher).cbz"),
            format: .cbz,
            displayTitle: publisher,
            publisher: publisher,
            language: language,
            genres: [genre],
            tags: [tag],
            origin: .inferred
        )
    }

    private func menu(readingIn language: String?) -> LibraryModel {
        InterfaceLanguage.choose(language)
        let model = LibraryModel()
        model.publications = Self.library
        return model
    }

    @Test("A French reader finds Éditions before Zenith")
    func publishersCollateInTheReadersLanguage() {
        let model = menu(readingIn: "fr")
        defer { InterfaceLanguage.choose(nil) }
        #expect(
            model.availablePublishers == [Self.accented, Self.plain],
            "the publisher filter filed an accent past the end of the alphabet"
        )
    }

    @Test("Genres and tags collate too, because they are read the same way")
    func genresAndTagsCollateInTheReadersLanguage() {
        let model = menu(readingIn: "fr")
        defer { InterfaceLanguage.choose(nil) }
        #expect(
            model.availableGenres == ["Épouvante", "Zombies"],
            "the genre filter filed an accent past the end of the alphabet"
        )
        #expect(
            model.availableTags == ["épisodique", "zines"],
            "the tag filter filed an accent past the end of the alphabet"
        )
    }

    /// Language codes are ASCII by definition, so this case cannot go red on an accent.
    ///
    /// It is here because nothing validates what a `ComicInfo.xml` writes into `<LanguageISO>`:
    /// a mis-tagged file carrying *Français* rather than *fr* reaches this list as it is
    /// spelled. The list is collated for that reason, not for the codes.
    @Test("The language filter is collated on whatever the files actually spell")
    func languagesAreCollatedToo() {
        let model = menu(readingIn: "fr")
        defer { InterfaceLanguage.choose(nil) }
        #expect(model.availableLanguages == ["fr", "zu"], "the language filter is not ordered")
    }

    /// The order is the reader's, so a reader who changes language changes the menu.
    ///
    /// Swedish files *Ö* and *Å* after *Z*, which is the opposite of what French does with an
    /// accent — so one library gives two orders and neither is the code point one.
    @Test("A reader who chose Swedish gets the Swedish order, not the French one")
    func theMenuFollowsTheChosenLanguage() {
        defer { InterfaceLanguage.choose(nil) }
        let swedish = [
            Self.publication(publisher: "Ödmjuk", genre: "g", tag: "t", language: "sv"),
            Self.publication(publisher: "Zenith Press", genre: "z", tag: "z", language: "zu"),
        ]

        InterfaceLanguage.choose("sv")
        let model = LibraryModel()
        model.publications = swedish
        #expect(
            model.availablePublishers == ["Zenith Press", "Ödmjuk"],
            "Swedish files Ö after Z, and the menu did not"
        )

        InterfaceLanguage.choose("fr")
        #expect(
            model.availablePublishers == ["Ödmjuk", "Zenith Press"],
            "French folds Ö onto O, and the menu did not"
        )
    }

    /// Two values that collate equal still come back in one fixed order.
    ///
    /// The collation is case-insensitive, matching the shelf's, so *marvel* and *Marvel* are
    /// the same value to it. They are different values to `Set`, whose iteration order is not
    /// fixed between runs — so without a tiebreak the menu could draw them either way round on
    /// two launches of the same library. A menu that reshuffles itself looks broken.
    @Test("Values that collate equal keep one order")
    func caseVariantsDoNotReshuffle() {
        defer { InterfaceLanguage.choose(nil) }
        InterfaceLanguage.choose("fr")
        let both = [
            Self.publication(publisher: "marvel", genre: "g", tag: "t", language: "fr"),
            Self.publication(publisher: "Marvel", genre: "z", tag: "z", language: "zu"),
        ]
        let model = LibraryModel()
        model.publications = both
        #expect(model.availablePublishers == ["Marvel", "marvel"], "the menu has no fixed order")
    }
}
