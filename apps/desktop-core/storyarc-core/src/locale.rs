//! Collation and formatting in the reader's language, through ICU4X (task 2.7 of
//! `desktop-clients`; design.md, Decision 5, item 10).
//!
//! `localization`: the interface switches to the language the reader chose, and the
//! library files a title where that language files it. The phones measured the same five
//! titles under Foundation and `java.text.Collator` and found three orders; ICU4X carries
//! the same CLDR tailorings, so the shelf on a desktop files *ñ* where Spanish files it and
//! *å* where Swedish files it. The four interface languages are English, French, German
//! and Spanish; Swedish is here because its order is the one that proves the collation is
//! asked at all.
//!
//! Everything here costs a data lookup at construction and nothing on the way back: build
//! one `Collation` per language change and keep it, as the apps keep a `Locale`.

use std::cmp::Ordering;

use icu::collator::options::{CollatorOptions, Strength};
use icu::collator::{Collator, CollatorBorrowed};
use icu::datetime::DateTimeFormatter;
use icu::datetime::fieldsets::YMD;
use icu::decimal::DecimalFormatter;
use icu::decimal::input::Decimal;
use icu::locale::Locale;
use icu::normalizer::DecomposingNormalizerBorrowed;
use icu::properties::CodePointMapData;
use icu::properties::props::GeneralCategory;

use crate::domain::Timestamp;

/// The reader's language, as a BCP 47 tag. `en` when the tag cannot be read, which is the
/// answer the phones give too: a shelf in the wrong language beats no shelf.
pub fn locale(tag: &str) -> Locale {
    Locale::try_from_str(tag).unwrap_or_else(|_| Locale::try_from_str("en").expect("en parses"))
}

/// Collates strings the way the reader's language files them: case-insensitive, accents
/// as the language ranks them.
pub struct Collation {
    collator: CollatorBorrowed<'static>,
    language: String,
}

impl Collation {
    /// Loads the tailoring for `tag`. One data lookup; keep the result.
    pub fn new(tag: &str) -> Self {
        let locale = locale(tag);
        let language = locale.id.language.to_string();
        let mut options = CollatorOptions::default();
        // Secondary strength: accents distinguish where the language says so, case does
        // not — the `.caseInsensitive` compare the shelf uses on iOS.
        options.strength = Some(Strength::Secondary);
        let collator = Collator::try_new((&locale).into(), options)
            .or_else(|_| Collator::try_new(Default::default(), options))
            .expect("the root collation is compiled in");
        Self { collator, language }
    }

    /// Three-way comparison under the language's collation.
    pub fn compare(&self, left: &str, right: &str) -> Ordering {
        self.collator.compare(left, right)
    }

    /// The comparison the shelf sorts by: the collation, then code points as a stable
    /// tiebreak, so two values that collate equal — *marvel* and *Marvel* — keep one order
    /// between launches rather than whichever a hash map handed over.
    pub fn compare_stable(&self, left: &str, right: &str) -> Ordering {
        self.compare(left, right).then_with(|| left.cmp(right))
    }

    /// A title as it should be alphabetised: its leading article in the interface
    /// language removed, so "The Sandman" files under S. Per language, because "la" is
    /// an article in French and Spanish and a syllable in English.
    pub fn sort_key<'a>(&self, title: &'a str) -> &'a str {
        sort_key(title, &self.language)
    }

    /// Collates two titles by their sort keys.
    pub fn compare_titles(&self, left: &str, right: &str) -> Ordering {
        self.compare(self.sort_key(left), self.sort_key(right))
    }

    pub fn language(&self) -> &str {
        &self.language
    }
}

/// The articles of the four interface languages StoryArc ships.
fn articles(language: &str) -> &'static [&'static str] {
    match language {
        "en" => &["the", "a", "an"],
        "fr" => &["le", "la", "les", "un", "une", "des", "l'"],
        "de" => &["der", "die", "das", "ein", "eine"],
        "es" => &["el", "la", "los", "las", "un", "una"],
        _ => &[],
    }
}

/// `Collation::sort_key`, for a caller that holds a language code and no collator.
pub fn sort_key<'a>(title: &'a str, language: &str) -> &'a str {
    let trimmed = title.trim();
    for article in articles(language) {
        // The apostrophe forms — French "l'" — carry no space after them.
        let prefix = if article.ends_with('\'') {
            (*article).to_owned()
        } else {
            format!("{article} ")
        };
        // Every article is ASCII, so a case-insensitive ASCII compare of the first bytes is
        // the `lowercased().hasPrefix` of iOS without lower-casing the whole title.
        let matches = trimmed
            .get(..prefix.len())
            .is_some_and(|head| head.eq_ignore_ascii_case(&prefix));
        if trimmed.len() > prefix.len() && matches {
            return trimmed[prefix.len()..].trim_start();
        }
    }
    trimmed
}

/// Case and accents removed, and nothing else, so "Café" answers "cafe" and "CAFE": the
/// search fold of `SearchRank` and `LibraryIndex`. Decompose, drop the non-spacing marks,
/// lower-case without a locale — spelled out rather than a full case fold, which would
/// turn "Straße" into "strasse" on one platform and not another.
pub fn fold(value: &str) -> String {
    let decomposed = DecomposingNormalizerBorrowed::new_nfd().normalize(value.trim());
    let categories = CodePointMapData::<GeneralCategory>::new();
    decomposed
        .chars()
        .filter(|c| categories.get(*c) != GeneralCategory::NonspacingMark)
        .flat_map(char::to_lowercase)
        .collect()
}

/// A whole number with the language's grouping: `1,234,567` in English, `1 234 567` in
/// French, `1.234.567` in German and Spanish.
pub fn format_integer(value: i64, tag: &str) -> String {
    let locale = locale(tag);
    let formatter = DecimalFormatter::try_new((&locale).into(), Default::default())
        .or_else(|_| DecimalFormatter::try_new(Default::default(), Default::default()))
        .expect("the root number symbols are compiled in");
    formatter.format_to_string(&Decimal::from(value))
}

/// A calendar date at medium length in the language: `30 Dec 2025` in English, `30 déc.
/// 2025` in French. The time of day is dropped, because a publication date and a finished
/// date are dates.
pub fn format_date(moment: Timestamp, tag: &str) -> String {
    let (year, month, day) = moment.civil();
    let Ok(date) = icu::calendar::Date::try_new_iso(year as i32, month as u8, day as u8) else {
        return moment.to_rfc3339()[..10].to_owned();
    };
    let locale = locale(tag);
    DateTimeFormatter::try_new((&locale).into(), YMD::medium())
        .or_else(|_| DateTimeFormatter::try_new(Default::default(), YMD::medium()))
        .map(|formatter| formatter.format(&date).to_string())
        .unwrap_or_else(|_| moment.to_rfc3339()[..10].to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Five titles whose order differs in each of three languages, the phones' own table.
    const TITLES: [&str; 5] = ["Zorro", "Ähre", "Nuez", "Ñandú", "Ångström"];

    fn shelf(language: &str) -> Vec<&'static str> {
        let collation = Collation::new(language);
        let mut titles = TITLES.to_vec();
        titles.sort_by(|a, b| collation.compare_stable(a, b));
        titles
    }

    #[test]
    fn spanish_files_enye_after_n() {
        assert_eq!(shelf("es"), ["Ähre", "Ångström", "Nuez", "Ñandú", "Zorro"]);
    }

    #[test]
    fn german_folds_a_diaeresis_onto_a() {
        assert_eq!(shelf("de"), ["Ähre", "Ångström", "Ñandú", "Nuez", "Zorro"]);
    }

    #[test]
    fn swedish_files_a_ring_and_a_diaeresis_after_z() {
        assert_eq!(shelf("sv"), ["Ñandú", "Nuez", "Zorro", "Ångström", "Ähre"]);
    }

    /// iOS's `LibrarySortSpeaksTheReadersLanguageTests` records that English files these five
    /// as German does; French folds the same way. The four interface languages, all stated.
    #[test]
    fn english_and_french_file_the_five_titles_as_german_does() {
        let german = ["Ähre", "Ångström", "Ñandú", "Nuez", "Zorro"];
        assert_eq!(shelf("en"), german);
        assert_eq!(shelf("fr"), german);
    }

    #[test]
    fn the_languages_disagree_so_each_answer_is_real() {
        let orders: std::collections::HashSet<Vec<&str>> =
            ["es", "de", "sv"].into_iter().map(shelf).collect();
        assert_eq!(orders.len(), 3);
    }

    /// The iPad sidebar's series cases: Spanish files *Nube* before *Ñu*, German the reverse,
    /// and three series put *Ñandú* last in Spanish.
    #[test]
    fn series_names_collate_as_the_ios_sidebar_does() {
        let sorted = |language: &str, names: &[&'static str]| {
            let collation = Collation::new(language);
            let mut names = names.to_vec();
            names.sort_by(|a, b| collation.compare_stable(a, b));
            names
        };
        assert_eq!(sorted("es", &["Ñu", "Nube"]), ["Nube", "Ñu"]);
        assert_eq!(sorted("de", &["Nube", "Ñu"]), ["Ñu", "Nube"]);
        assert_eq!(
            sorted("es", &["Ñandú", "Nube", "Nuez"]),
            ["Nube", "Nuez", "Ñandú"]
        );
    }

    #[test]
    fn english_and_french_file_an_accent_inside_the_alphabet() {
        for language in ["en", "fr"] {
            let collation = Collation::new(language);
            let mut names = ["Zenith Press", "Éditions du Lombard"];
            names.sort_by(|a, b| collation.compare_stable(a, b));
            assert_eq!(names, ["Éditions du Lombard", "Zenith Press"], "{language}");
        }
        let swedish = Collation::new("sv");
        assert_eq!(swedish.compare("Ödmjuk", "Zenith Press"), Ordering::Greater);
        let french = Collation::new("fr");
        assert_eq!(french.compare("Ödmjuk", "Zenith Press"), Ordering::Less);
    }

    #[test]
    fn values_that_collate_equal_keep_one_order() {
        let collation = Collation::new("fr");
        assert_eq!(collation.compare("marvel", "Marvel"), Ordering::Equal);
        let mut both = ["marvel", "Marvel"];
        both.sort_by(|a, b| collation.compare_stable(a, b));
        assert_eq!(both, ["Marvel", "marvel"]);
    }

    #[test]
    fn a_leading_article_is_dropped_in_its_own_language_only() {
        assert_eq!(sort_key("The Sandman", "en"), "Sandman");
        assert_eq!(sort_key("A Contract with God", "en"), "Contract with God");
        assert_eq!(sort_key("La Brea", "en"), "La Brea");
        assert_eq!(sort_key("La Brea", "es"), "Brea");
        assert_eq!(sort_key("L'Étranger", "fr"), "Étranger");
        assert_eq!(sort_key("The", "en"), "The");
        let english = Collation::new("en");
        let mut titles = ["The Sandman", "Akira", "Bone"];
        titles.sort_by(|a, b| english.compare_titles(a, b));
        assert_eq!(titles, ["Akira", "Bone", "The Sandman"]);
    }

    #[test]
    fn the_search_fold_drops_case_and_accents_and_nothing_else() {
        assert_eq!(fold("Café"), "cafe");
        assert_eq!(fold("  CAFE "), "cafe");
        assert_eq!(fold("Straße"), "straße");
        assert_eq!(fold("Ñandú"), "nandu");
    }

    #[test]
    fn whole_numbers_group_in_the_languages_own_way() {
        assert_eq!(format_integer(1_234_567, "en"), "1,234,567");
        assert_eq!(format_integer(1_234_567, "de"), "1.234.567");
        assert_eq!(format_integer(1_234_567, "es"), "1.234.567");
        assert_eq!(format_integer(1_234_567, "fr"), "1\u{202f}234\u{202f}567");
        assert_eq!(format_integer(-42, "en"), "-42");
    }

    #[test]
    fn a_date_reads_in_the_languages_own_way() {
        let moment = Timestamp::parse_rfc3339("2025-12-30T13:06:40Z").unwrap();
        assert_eq!(format_date(moment, "en-GB"), "30 Dec 2025");
        assert_eq!(format_date(moment, "en-US"), "Dec 30, 2025");
        assert_eq!(format_date(moment, "fr"), "30 déc. 2025");
        assert_eq!(format_date(moment, "de"), "30.12.2025");
        assert_eq!(format_date(moment, "es"), "30 dic 2025");
    }

    #[test]
    fn an_unknown_tag_falls_back_to_english() {
        assert_eq!(locale("not a tag!").to_string(), "en");
        assert_eq!(Collation::new("zz-ZZ").language(), "zz");
    }
}
