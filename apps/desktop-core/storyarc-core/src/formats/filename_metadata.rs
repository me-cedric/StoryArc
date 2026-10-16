//! Series, volume, issue and year guessed from a filename. Mirrored from
//! `FilenameMetadata.swift`.
//!
//! `publication-formats` requires this when a publication carries no embedded metadata, and
//! requires the results to be **marked as inferred**: a later authoritative source — a
//! Kavita server, an OPDS catalogue, a `ComicInfo.xml` added afterwards — must be able to
//! replace a guess without asking the user to resolve a conflict it invented. So
//! `is_inferred` is always true here; the flag travels with the values, because a guess
//! that loses its label becomes indistinguishable from a fact.
//!
//! ponytail: an ordered set of patterns over one string, not a grammar. Comic filenames
//! have no syntax to parse — they have conventions, and the honest model of a convention is
//! a list of shapes tried in order. The cases the list must handle live in the shared corpus
//! manifest, so every platform agrees on what "common naming pattern" means.

use regex_lite::Regex;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FilenameMetadata {
    pub series: Option<String>,
    /// Issue or chapter. A string for the same reason `ComicInfo::number` is one.
    pub number: Option<String>,
    pub volume: Option<i64>,
    pub year: Option<i64>,
    /// Always true. Every value here is a guess, and the point is that it says so.
    pub is_inferred: bool,
}

impl FilenameMetadata {
    /// Reads what a filename implies. The extension is ignored, and a name that implies
    /// nothing yields a series and nothing else.
    ///
    /// `series_hint` is what the containing folder is called, used only when the filename
    /// yields no series of its own; `catalogued` is what a server that keeps the library
    /// calls it, which wins over both.
    pub fn new(filename: &str, series_hint: Option<&str>, catalogued: Option<&str>) -> Self {
        // A dotfile is not a publication, and stripping the extension would otherwise read
        // ".cbz" as a series called "cbz".
        if filename.starts_with('.') {
            return Self {
                series: None,
                number: None,
                volume: None,
                year: None,
                is_inferred: true,
            };
        }
        let mut stem = strip_extension(filename).to_owned();

        // Bracketed groups — scanlation credits, quality tags, language tags — are never part
        // of a title, and leaving them in makes every file from one group look like a
        // different series.
        stem = removing_bracketed(&stem);

        // The year first, and only from parentheses. A bare four-digit number is ambiguous:
        // "Blame! 2001" is a title. Parentheses are what make it a claim about a date.
        let mut year = None;
        if let Some((whole, value)) = last_parenthesised_year(&stem) {
            year = value.parse().ok();
            stem = stem.replacen(&whole, " ", 1);
        }

        // Volume, before the issue number: `v02` and `Vol. 3` would otherwise be read as
        // issues. Then `(v104)`, a manga convention the year pass leaves behind.
        let mut volume = None;
        for pattern in [r"(?i)\bv(?:ol)?\.?\s*(\d{1,4})\b", r"(?i)\(v(\d{1,4})\)"] {
            if let Some((whole, value)) = first_match(pattern, &stem) {
                volume = value.parse().ok();
                stem = stem.replacen(&whole, " ", 1);
                break;
            }
        }

        // The issue or chapter, most explicit marker first. A trailing bare number is last,
        // because it is the weakest signal and the one that misreads a title. It is capped
        // at three digits: four is where a number stops looking like an issue and starts
        // looking like part of the title, and every convention that goes that high uses an
        // explicit marker ("c1044", not "1044"). `(?:^|\s)` rather than `\s`, so a name that
        // is *only* a number — "003.cbz" inside a per-series folder — reads as issue three
        // with no series, leaving the folder to supply one.
        let mut number = None;
        for pattern in [
            r"(?i)#\s*(\d{1,5}(?:\.\d+)?)",
            r"(?i)\bc(?:h(?:apter)?)?\.?\s*(\d{1,5}(?:\.\d+)?)\b",
            r"(?:^|\s)(\d{1,3}(?:\.\d+)?)\s*$",
        ] {
            if let Some((whole, value)) = first_match(pattern, &stem) {
                number = Some(trimming_leading_zeros(&value));
                stem = stem.replacen(&whole, " ", 1);
                break;
            }
        }

        // The catalogue first, when there is one; then the filename, because a folder name
        // describes a shelf and a filename describes the book on it.
        let series = catalogued
            .map(str::to_owned)
            .or_else(|| tidy_series(&stem))
            .or_else(|| series_hint.map(str::to_owned));

        Self {
            series,
            number,
            volume,
            year,
            is_inferred: true,
        }
    }
}

fn strip_extension(filename: &str) -> &str {
    match filename.rfind('.') {
        Some(dot) if dot > 0 => &filename[..dot],
        _ => filename,
    }
}

/// The whole match and its first group.
fn first_match(pattern: &str, text: &str) -> Option<(String, String)> {
    let regex = Regex::new(pattern).ok()?;
    let captures = regex.captures(text)?;
    Some((
        captures.get(0)?.as_str().to_owned(),
        captures.get(1)?.as_str().to_owned(),
    ))
}

/// The last parenthesised four-digit group that is a plausible publication year.
///
/// Last rather than first: a title may contain parentheses of its own, and the year
/// conventionally comes after the title. Comics predate 1900 nowhere, and a four-digit
/// number past next century is something else.
fn last_parenthesised_year(text: &str) -> Option<(String, String)> {
    let regex = Regex::new(r"\((\d{4})\)").ok()?;
    regex
        .captures_iter(text)
        .filter_map(|captures| {
            let whole = captures.get(0)?.as_str().to_owned();
            let value = captures.get(1)?.as_str().to_owned();
            let year: i64 = value.parse().ok()?;
            (1900..=2200).contains(&year).then_some((whole, value))
        })
        .last()
}

fn removing_bracketed(text: &str) -> String {
    let mut out = text.to_owned();
    for pattern in [r"\[[^\]]*\]", r"\{[^}]*\}"] {
        if let Ok(regex) = Regex::new(pattern) {
            out = regex.replace_all(&out, " ").into_owned();
        }
    }
    out
}

/// "#01" and "#1" are the same issue, and a library that sorts them apart looks broken. A
/// value that is all zeros stays "0".
fn trimming_leading_zeros(value: &str) -> String {
    let trimmed = value.trim_start_matches('0');
    if trimmed.is_empty() || trimmed.starts_with('.') {
        if value.starts_with('0') {
            "0".to_owned()
        } else {
            value.to_owned()
        }
    } else {
        trimmed.to_owned()
    }
}

/// What is left after the markers are removed, as a title. Separators left dangling by a
/// removed marker — "One Piece - " and "Invincible #" — come back as the title alone.
fn tidy_series(text: &str) -> Option<String> {
    let collapsed: Vec<&str> = text.split_whitespace().collect();
    let out = collapsed
        .join(" ")
        .trim_matches(|c: char| " -–—_#.,:;()".contains(c))
        .to_owned();
    (!out.is_empty()).then_some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_dotfile_is_not_a_publication() {
        let meta = FilenameMetadata::new(".cbz", None, None);
        assert_eq!(meta.series, None);
        assert!(meta.is_inferred);
    }

    #[test]
    fn the_folder_supplies_a_series_only_when_the_name_has_none() {
        assert_eq!(
            FilenameMetadata::new("003.cbz", Some("Saga"), None)
                .series
                .as_deref(),
            Some("Saga")
        );
        assert_eq!(
            FilenameMetadata::new("Saga 003.cbz", Some("Folder"), None)
                .series
                .as_deref(),
            Some("Saga")
        );
        assert_eq!(
            FilenameMetadata::new("Saga 003.cbz", None, Some("Catalogued"))
                .series
                .as_deref(),
            Some("Catalogued")
        );
    }

    #[test]
    fn leading_zeros_are_dropped_and_a_zero_stays_a_zero() {
        assert_eq!(trimming_leading_zeros("011"), "11");
        assert_eq!(trimming_leading_zeros("000"), "0");
        // The Swift reference answers "0" here too: a fraction with no whole part reads as
        // issue zero. Pinned so the three implementations agree; whether it should is a
        // question for the owners of all three, not for one of them.
        assert_eq!(trimming_leading_zeros("0.5"), "0");
        assert_eq!(trimming_leading_zeros("3.5"), "3.5");
    }
}
