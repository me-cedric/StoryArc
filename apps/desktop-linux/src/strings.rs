//! The interface strings: the four gettext catalogues the parent generates from the iOS
//! string catalogues (`po/<lang>.po`, task 2.8), read at launch in the session's
//! language.
//!
//! The catalogues are embedded, so a tree run and a Flatpak see the same strings and no
//! `.mo` file has to be installed. The reader is a small PO parser rather than the C
//! gettext library: it needs no new dependency and no locale setup, and it tests on any
//! host. The app follows the system's language list (`desktop-experience`, Language
//! follows the system); when none of the four matches, English is used and no key is
//! ever shown.
//!
//! A desktop-only string the iOS catalogue does not hold falls back to the English
//! text the caller passes, in every language. The lane report lists those keys for
//! the parent to add to the catalogue.

use std::collections::HashMap;
use std::sync::OnceLock;

const CATALOGUES: [(&str, &str); 4] = [
    ("en", include_str!("../po/en.po")),
    ("de", include_str!("../po/de.po")),
    ("es", include_str!("../po/es.po")),
    ("fr", include_str!("../po/fr.po")),
];

/// One entry: the singular text, and the plural forms when the key has them.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct Entry {
    singular: String,
    plurals: Vec<String>,
}

/// A parsed catalogue.
#[derive(Clone, Debug, Default)]
pub struct Catalogue {
    language: String,
    entries: HashMap<String, Entry>,
}

impl Catalogue {
    /// Parses PO text. Entries with an empty translation are skipped, so the English
    /// fallback shows instead of a blank.
    pub fn parse(language: &str, text: &str) -> Self {
        let mut entries = HashMap::new();
        let mut key: Option<String> = None;
        let mut entry = Entry::default();
        let mut target: Target = Target::None;

        let finish =
            |key: &mut Option<String>, entry: &mut Entry, entries: &mut HashMap<String, Entry>| {
                if let Some(id) = key.take() {
                    let done = std::mem::take(entry);
                    if !id.is_empty() && !done.singular.is_empty() {
                        entries.insert(id, done);
                    }
                }
            };

        for raw in text.lines() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some(rest) = line.strip_prefix("msgid ") {
                finish(&mut key, &mut entry, &mut entries);
                key = Some(unquote(rest));
                target = Target::Key;
            } else if let Some(rest) = line.strip_prefix("msgid_plural ") {
                let _ = unquote(rest);
                target = Target::None;
            } else if let Some(rest) = line.strip_prefix("msgstr[") {
                let (index, rest) = rest.split_once(']').unwrap_or(("0", ""));
                let index: usize = index.parse().unwrap_or(0);
                if entry.plurals.len() <= index {
                    entry.plurals.resize(index + 1, String::new());
                }
                entry.plurals[index] = unquote(rest.trim_start());
                if index == 0 {
                    entry.singular.clone_from(&entry.plurals[0]);
                }
                target = Target::Plural(index);
            } else if let Some(rest) = line.strip_prefix("msgstr ") {
                entry.singular = unquote(rest);
                target = Target::Singular;
            } else if line.starts_with('"') {
                let piece = unquote(line);
                match target {
                    Target::Key => {
                        if let Some(id) = key.as_mut() {
                            id.push_str(&piece);
                        }
                    }
                    Target::Singular => entry.singular.push_str(&piece),
                    Target::Plural(index) => {
                        if let Some(form) = entry.plurals.get_mut(index) {
                            form.push_str(&piece);
                        }
                        if index == 0 {
                            entry.singular.push_str(&piece);
                        }
                    }
                    Target::None => {}
                }
            }
        }
        finish(&mut key, &mut entry, &mut entries);
        Self {
            language: language.to_owned(),
            entries,
        }
    }

    pub fn language(&self) -> &str {
        &self.language
    }

    /// The translation of `key`, when the catalogue has it.
    pub fn get(&self, key: &str) -> Option<&str> {
        self.entries.get(key).map(|entry| entry.singular.as_str())
    }

    /// The plural form for `count`, when the catalogue has the key.
    pub fn get_plural(&self, key: &str, count: u64) -> Option<&str> {
        let entry = self.entries.get(key)?;
        if entry.plurals.is_empty() {
            return Some(&entry.singular);
        }
        let index = plural_index(&self.language, count).min(entry.plurals.len() - 1);
        Some(&entry.plurals[index])
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

#[derive(Clone, Copy)]
enum Target {
    None,
    Key,
    Singular,
    Plural(usize),
}

/// The plural rule of each catalogue's header. French counts 0 and 1 as singular.
fn plural_index(language: &str, count: u64) -> usize {
    match language {
        "fr" => usize::from(count > 1),
        _ => usize::from(count != 1),
    }
}

/// Reads a PO string literal, with its escapes.
fn unquote(text: &str) -> String {
    let inner = text.trim().trim_start_matches('"').trim_end_matches('"');
    let mut out = String::with_capacity(inner.len());
    let mut chars = inner.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some('"') => out.push('"'),
            Some('\\') => out.push('\\'),
            Some(other) => {
                out.push('\\');
                out.push(other);
            }
            None => out.push('\\'),
        }
    }
    out
}

/// The catalogue language for a system language list such as
/// `["fr_CH.UTF-8", "fr_CH", "fr", "en", "C"]`: the first entry one of the four
/// catalogues serves, else English.
pub fn pick_language<S: AsRef<str>>(names: &[S]) -> &'static str {
    names
        .iter()
        .map(|name| {
            let name = name.as_ref();
            let end = name.find(['_', '.', '@', '-']).unwrap_or(name.len());
            name[..end].to_ascii_lowercase()
        })
        .find_map(|code| {
            CATALOGUES
                .iter()
                .map(|(language, _)| *language)
                .find(|language| *language == code)
        })
        .unwrap_or("en")
}

static CATALOGUE: OnceLock<Catalogue> = OnceLock::new();

/// Loads the catalogue for the system language list, once.
pub fn init<S: AsRef<str>>(system_languages: &[S]) -> &'static Catalogue {
    CATALOGUE.get_or_init(|| {
        let language = pick_language(system_languages);
        let text = CATALOGUES
            .iter()
            .find(|(candidate, _)| *candidate == language)
            .map(|(_, text)| *text)
            .unwrap_or(CATALOGUES[0].1);
        Catalogue::parse(language, text)
    })
}

/// The language the catalogue speaks, for the collation and the formats: English
/// before `init` has run.
pub fn language() -> &'static str {
    CATALOGUE.get().map_or("en", Catalogue::language)
}

/// The string for `key`, or `english` where the catalogue has no entry (and before
/// `init` has run, which only tests do).
pub fn tr(key: &str, english: &str) -> String {
    CATALOGUE
        .get()
        .and_then(|catalogue| catalogue.get(key))
        .unwrap_or(english)
        .to_owned()
}

/// `tr` with the catalogue's `%s`, `%d` and positional `%1$s` placeholders filled in order.
pub fn tr_args(key: &str, english: &str, args: &[&dyn std::fmt::Display]) -> String {
    fill(&tr(key, english), args)
}

/// Fills printf-style placeholders: `%s`, `%d`, `%@`, and positional `%1$s`.
pub fn fill(template: &str, args: &[&dyn std::fmt::Display]) -> String {
    let mut out = String::with_capacity(template.len());
    let mut next = 0;
    let mut rest = template;
    while let Some(at) = rest.find('%') {
        out.push_str(&rest[..at]);
        let after = &rest[at + 1..];
        if let Some(escaped) = after.strip_prefix('%') {
            out.push('%');
            rest = escaped;
            continue;
        }
        let digits: String = after.chars().take_while(char::is_ascii_digit).collect();
        let mut consumed = digits.len();
        let index = if !digits.is_empty() && after[consumed..].starts_with('$') {
            consumed += 1;
            digits.parse::<usize>().unwrap_or(1).saturating_sub(1)
        } else {
            consumed = 0;
            let index = next;
            next += 1;
            index
        };
        // The conversion letter: s, d, @, or a width such as `%2d`.
        let letter_at = after[consumed..].find(|c: char| c.is_ascii_alphabetic() || c == '@');
        match letter_at {
            Some(offset) => {
                match args.get(index) {
                    Some(arg) => out.push_str(&arg.to_string()),
                    None => out.push_str(&rest[at..at + 1 + consumed + offset + 1]),
                }
                rest = &after[consumed + offset + 1..];
            }
            None => {
                out.push_str(&rest[at..]);
                rest = "";
            }
        }
    }
    out.push_str(rest);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"
# A comment
msgid ""
msgstr ""
"Language: fr\n"
"Plural-Forms: nplurals=2; plural=(n > 1);\n"

msgid "settings.title"
msgstr "Réglages"

msgid "about.version %s %s"
msgstr "StoryArc %1$s (%2$s)"

msgid "library.cell.pages %d"
msgid_plural "library.cell.pages %d"
msgstr[0] "%d page"
msgstr[1] "%d pages"

msgid "long.key"
msgstr ""
"Première ligne\n"
"« citée »"

msgid "empty.key"
msgstr ""
"#;

    #[test]
    fn the_four_catalogues_parse_and_hold_the_same_keys() {
        let en = Catalogue::parse("en", CATALOGUES[0].1);
        assert!(en.len() > 1000, "{} keys", en.len());
        for (language, text) in &CATALOGUES[1..] {
            let catalogue = Catalogue::parse(language, text);
            assert_eq!(catalogue.len(), en.len(), "{language} differs from en");
            assert_eq!(
                catalogue.get("settings.title").map(str::is_empty),
                Some(false)
            );
        }
    }

    #[test]
    fn a_catalogue_reads_singulars_plurals_continuations_and_escapes() {
        let fr = Catalogue::parse("fr", SAMPLE);
        assert_eq!(fr.get("settings.title"), Some("Réglages"));
        assert_eq!(fr.get("long.key"), Some("Première ligne\n« citée »"));
        assert_eq!(fr.get("empty.key"), None, "an empty translation falls back");
        assert_eq!(fr.get("missing.key"), None);
        assert_eq!(fr.get_plural("library.cell.pages %d", 0), Some("%d page"));
        assert_eq!(fr.get_plural("library.cell.pages %d", 1), Some("%d page"));
        assert_eq!(fr.get_plural("library.cell.pages %d", 2), Some("%d pages"));
        assert_eq!(fr.get_plural("settings.title", 5), Some("Réglages"));
        let en = Catalogue::parse("en", SAMPLE);
        assert_eq!(en.get_plural("library.cell.pages %d", 0), Some("%d pages"));
    }

    #[test]
    fn the_system_language_list_picks_the_first_catalogue_it_names() {
        assert_eq!(
            pick_language(&["fr_CH.UTF-8", "fr_CH", "fr", "en", "C"]),
            "fr"
        );
        assert_eq!(pick_language(&["de_DE", "C"]), "de");
        assert_eq!(pick_language(&["es-ES"]), "es");
        assert_eq!(pick_language(&["it_IT", "pt_BR", "C"]), "en");
        assert_eq!(pick_language(&["ja", "de"]), "de");
        assert_eq!(pick_language::<&str>(&[]), "en");
        assert_eq!(pick_language(&["EN_GB"]), "en");
    }

    #[test]
    fn placeholders_fill_in_order_and_by_position() {
        let version = &"1.2.0" as &dyn std::fmt::Display;
        let build = &"42" as &dyn std::fmt::Display;
        assert_eq!(
            fill("StoryArc %1$s (%2$s)", &[version, build]),
            "StoryArc 1.2.0 (42)"
        );
        assert_eq!(fill("%2$s then %1$s", &[version, build]), "42 then 1.2.0");
        assert_eq!(fill("%d pages of %s", &[&12, &"Saga"]), "12 pages of Saga");
        assert_eq!(fill("100%% done", &[]), "100% done");
        assert_eq!(
            fill("%s and %s", &[&"one"]),
            "one and %s",
            "a missing argument shows the placeholder"
        );
        assert_eq!(fill("no placeholder", &[&1]), "no placeholder");
        assert_eq!(fill("trailing %", &[]), "trailing %");
    }

    #[test]
    fn tr_falls_back_to_english_before_init_and_for_a_desktop_only_key() {
        assert_eq!(tr("desktop.command.openFile", "Open File…"), "Open File…");
        assert_eq!(tr_args("missing %s", "Hello %s", &[&"you"]), "Hello you");
    }
}
