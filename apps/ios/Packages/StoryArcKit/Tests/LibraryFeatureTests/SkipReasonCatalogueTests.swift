import Foundation
import Testing

@testable import LibraryFeature

/// Every refusal a scan can report has a sentence in all four languages.
///
/// `localization`'s *Supported languages* and *A refusal speaks the reader's language*: a
/// reader whose library refuses a file is the reader who most needs to understand, and until
/// this change those seven sentences were English literals in `StoryArcKit/Sources/Formats`
/// — a module with no catalogue, which is why `pnpm strings:ios` never reported them.
///
/// **The catalogue is read as a file, not resolved at run time.** `swift build` copies an
/// `.xcstrings` without compiling it, so `String(localized:)` answers with the key itself on
/// the host — measured, and the reason `PlayerLabels` states the same limit. A host test that
/// asserted French prose would be asserting a lookup that cannot work where it runs.
///
/// `SkipReasonWordsTests` beside this one asserts that every case reaches one of these keys.
/// This suite asserts the keys are answerable; that one asserts they are asked for.
@Suite("Every skipped-publication reason is worded in four languages")
struct SkipReasonCatalogueTests {

    /// The four `localization` names. English is the one every other falls back to.
    private static let languages = ["en", "fr", "de", "es"]

    /// The keys the library's catalogue has to answer, one per refusal the scan can report.
    ///
    /// Written out rather than derived from `SkipReason`, deliberately: a derived list would
    /// pass on a case whose key was a typo, because both sides would carry the same typo.
    static let keys = [
        "library.skipped.reason.unsupported %@",
        "library.skipped.reason.notThere",
        "library.skipped.reason.formatNotRecognised",
        "library.skipped.reason.archivePasswordProtected",
        "library.skipped.reason.archiveUnreadable",
        "library.skipped.reason.pdfUnopenable",
        "library.skipped.reason.contentProtected",
        "library.skipped.reason.unknown",
    ]

    @Test("The catalogue defines a translated value for every reason, in every language")
    func everyReasonIsTranslated() throws {
        for key in Self.keys {
            let localizations = try #require(
                LibraryFeatureSource.localizationsIfAny(of: key),
                "the catalogue defines no \"\(key)\""
            )
            for language in Self.languages {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"]
                let state = (unit as? [String: Any])?["state"] as? String
                let value = (unit as? [String: Any])?["value"] as? String
                #expect(state == "translated", "\"\(key)\" is not translated into \(language)")
                #expect(value?.isEmpty == false, "\"\(key)\" is empty in \(language)")
            }
        }
    }

    /// The one refusal whose two platforms disagreed, and how it was settled.
    ///
    /// iOS said *it is protected by its store's content protection*; Android named the kind of
    /// thing. `localization`'s *One sentence, assembled differently* settles it: "where the
    /// sentences genuinely differ in what they tell the reader — one naming a place the other
    /// leaves unnamed — the more informative one is the agreed wording". Android's wins, and
    /// `values/strings.xml` holds the same English.
    @Test("The content-protection sentence is Android's wording, on both platforms")
    func contentProtectionIsReconciled() throws {
        let localizations = try #require(
            LibraryFeatureSource.localizationsIfAny(of: "library.skipped.reason.contentProtected")
        )
        let english = (localizations["en"] as? [String: Any])?["stringUnit"] as? [String: Any]

        #expect(
            english?["value"] as? String
                == "this audiobook is protected by its store’s content protection"
        )
    }

    /// What a prompt would have to say, in all four languages.
    ///
    /// A translator writes in one language, so a list of English tokens guards English alone.
    /// The first six are the list `AudiobookIndexingTests` applied to the English sentence
    /// before the words moved; the rest are the same four ideas — a key, a password, an
    /// account, a way to sign in — in the three languages that sentence is now also written
    /// in. `activation` is spelt the same in English and French.
    ///
    /// Every token is matched against every language, because a French word has no business
    /// in the German refusal either.
    private static let promptWords = [
        "key", "password", "account", "activation", "sign in", "log in",
        "clé", "mot de passe", "compte", "connexion", "connecter",
        "schlüssel", "passwort", "konto", "anmeld", "aktivierung",
        "clave", "contraseña", "cuenta", "sesión", "activación",
    ]

    /// The locked refusal prompts for nothing, in every language.
    ///
    /// `publication-formats` keeps that case payload-free because there is no key to ask for
    /// and no account to name. A translation is a second place the promise can be broken, and
    /// it moved here when the sentence did: `AudiobookIndexingTests` asserted this in English
    /// while the words lived in the format layer, and now the words live in four files.
    @Test("The locked refusal asks for no key, no account and no activation, in any language")
    func theLockedRefusalPromptsForNothing() throws {
        let localizations = try #require(
            LibraryFeatureSource.localizationsIfAny(of: "library.skipped.reason.contentProtected")
        )
        for language in Self.languages {
            let unit = (localizations[language] as? [String: Any])?["stringUnit"]
            let value = ((unit as? [String: Any])?["value"] as? String ?? "").lowercased()
            for asked in Self.promptWords {
                #expect(!value.contains(asked), "the \(language) refusal mentions \(asked)")
            }
        }
    }
}
