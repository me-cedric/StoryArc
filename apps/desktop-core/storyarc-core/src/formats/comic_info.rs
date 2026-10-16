//! The metadata a comic archive carries in `ComicInfo.xml`. Mirrored from `ComicInfo.swift`.
//!
//! `publication-formats` names thirteen fields plus a reading direction, and this is all of
//! them. The format is the de-facto ComicRack schema that every comic tool writes: a flat
//! list of elements, plus an optional `<Pages>` list that can designate a cover other than
//! page 1 and mark double-page spreads.
//!
//! Every field is optional, because every field is optional in practice. A file with only
//! `<Series>` is common, and a parser that requires more of them finds nothing in a real
//! library.

use std::collections::HashMap;

use super::byte_reader::latin1;
use super::xml;
use crate::domain::ReadingDirection;

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ComicInfo {
    pub series: Option<String>,
    /// Issue or chapter number. A string, not a number: "3.5" and "Annual 1" are both real,
    /// and rounding either loses the publication's identity.
    pub number: Option<String>,
    pub volume: Option<i64>,
    pub title: Option<String>,
    pub summary: Option<String>,
    /// `ComicInfo` allows a comma-separated list in every creator field.
    pub writers: Vec<String>,
    pub pencillers: Vec<String>,
    pub publisher: Option<String>,
    pub year: Option<i64>,
    pub month: Option<i64>,
    pub day: Option<i64>,
    /// The publisher's own page count. Treated as a claim, not a fact — the archive's
    /// actual page list is the authority.
    pub page_count: Option<i64>,
    pub language: Option<String>,
    /// `<Genre>` — the shelf the publication belongs on, comma-separated.
    pub genres: Vec<String>,
    /// `<Tags>` — whatever else the cataloguer recorded, comma-separated.
    pub tags: Vec<String>,
    /// The direction the publication declares, or `None` when it declares none.
    ///
    /// `Manga=YesAndRightToLeft` is a declaration. `Manga=Yes` is **not**: it says the
    /// publication is manga, which is not the same as saying which way it reads, and plenty
    /// of manga are published left-to-right in translation. So `Yes` falls through to the
    /// language rule rather than assuming.
    pub declared_direction: Option<ReadingDirection>,
    /// Where the cover is, when `<Pages>` designates one that is not the first.
    pub cover_page_index: Option<usize>,
    /// Pages `<Pages>` marks as double-page spreads. Believed in preference to guessing
    /// from aspect ratio: a heuristic versus a statement.
    pub double_page_indices: Vec<usize>,
    /// Pages `<Pages>` marks with a `Bookmark`, in reading order.
    pub chapter_start_indices: Vec<usize>,
    /// The `Bookmark` attribute's own text, by the page it marks.
    pub chapter_titles: HashMap<usize, String>,
}

impl ComicInfo {
    /// Parses `ComicInfo.xml`. Returns `None` only when the bytes are not ComicInfo at all
    /// — a file with no recognised fields still yields an empty `ComicInfo`, because
    /// "present but empty" and "absent" are different states.
    pub fn parse(data: &[u8]) -> Option<Self> {
        let text = std::str::from_utf8(data).map_or_else(|_| latin1(data), str::to_owned);
        if !text.contains("<ComicInfo") {
            return None;
        }

        let value = |name: &str| -> Option<String> {
            let trimmed = xml::element_body(&text, name)?.trim();
            (!trimmed.is_empty()).then(|| xml::unescape(trimmed))
        };
        let list = |name: &str| -> Vec<String> {
            value(name)
                .unwrap_or_default()
                .split(',')
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_owned)
                .collect()
        };
        let number = |name: &str| value(name).and_then(|v| v.parse::<i64>().ok());

        let declared_direction = match value("Manga").map(|v| v.to_lowercase()).as_deref() {
            Some("yesandrighttoleft") => Some(ReadingDirection::RightToLeft),
            Some("no") => Some(ReadingDirection::LeftToRight),
            _ => None,
        };

        let pages = Self::read_pages(&text);
        Some(Self {
            series: value("Series"),
            number: value("Number"),
            volume: number("Volume"),
            title: value("Title"),
            summary: value("Summary"),
            writers: list("Writer"),
            pencillers: list("Penciller"),
            publisher: value("Publisher"),
            year: number("Year"),
            month: number("Month"),
            day: number("Day"),
            page_count: number("PageCount"),
            language: value("LanguageISO").or_else(|| value("Language")),
            genres: list("Genre"),
            tags: list("Tags"),
            declared_direction,
            // Index 0 is the default, so designating it carries no information and is
            // dropped — otherwise every well-formed file would look like an override.
            cover_page_index: pages.cover.filter(|&index| index != 0),
            double_page_indices: pages.spreads,
            chapter_start_indices: pages.chapters,
            chapter_titles: pages.titles,
        })
    }

    /// The direction the reader should open in: an explicit declaration wins, otherwise
    /// Japanese opens right-to-left.
    pub fn reading_direction(&self) -> ReadingDirection {
        ReadingDirection::inferred(self.declared_direction, self.language.as_deref())
    }

    /// What `<Page Image="n" .../>` declares, read once over the whole `<Pages>` list.
    /// `Image` is the page's index, which is not necessarily its position in the list.
    fn read_pages(text: &str) -> PageDeclaration {
        let mut declaration = PageDeclaration::default();
        for attributes in Self::page_elements(text) {
            let Some(index) = attributes
                .get("Image")
                .and_then(|v| v.trim().parse::<usize>().ok())
            else {
                continue;
            };
            if attributes.get("Type").map(String::as_str) == Some("FrontCover")
                && declaration.cover.is_none()
            {
                declaration.cover = Some(index);
            }
            if attributes
                .get("DoublePage")
                .is_some_and(|v| v.eq_ignore_ascii_case("true"))
            {
                declaration.spreads.push(index);
            }
            if let Some(bookmark) = attributes.get("Bookmark") {
                let trimmed = bookmark.trim();
                if !trimmed.is_empty() {
                    declaration.chapters.push(index);
                    declaration.titles.insert(index, trimmed.to_owned());
                }
            }
        }
        declaration.spreads.sort_unstable();
        declaration.chapters.sort_unstable();
        declaration
    }

    fn page_elements(text: &str) -> Vec<xml::Attributes> {
        let mut found = Vec::new();
        let mut rest = text;
        while let Some(open) = rest.find("<Page ") {
            rest = &rest[open + "<Page ".len()..];
            let Some(end) = rest.find('>') else { break };
            found.push(xml::parse_attributes(&rest[..end]));
            rest = &rest[end..];
        }
        found
    }
}

/// What one `<Pages>` list declares, in one pass.
#[derive(Default)]
struct PageDeclaration {
    cover: Option<usize>,
    spreads: Vec<usize>,
    chapters: Vec<usize>,
    titles: HashMap<usize, String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parsed(xml: &str) -> ComicInfo {
        ComicInfo::parse(xml.as_bytes()).expect("ComicInfo parses")
    }

    #[test]
    fn genre_and_tags_are_separate_comma_split_lists() {
        let info = parsed(
            "<ComicInfo><Genre>Superhero, Mystery</Genre><Tags>reprint,annual</Tags></ComicInfo>",
        );
        assert_eq!(info.genres, ["Superhero", "Mystery"]);
        assert_eq!(info.tags, ["reprint", "annual"]);
        let bare = parsed("<ComicInfo><Series>Bone</Series></ComicInfo>");
        assert!(bare.genres.is_empty() && bare.tags.is_empty());
        assert!(
            parsed("<ComicInfo><Genre></Genre></ComicInfo>")
                .genres
                .is_empty()
        );
        assert_eq!(
            parsed("<ComicInfo><Genre>Sword &amp; Sorcery</Genre></ComicInfo>").genres,
            ["Sword & Sorcery"]
        );
    }

    #[test]
    fn the_issue_number_stays_a_string() {
        assert_eq!(
            parsed("<ComicInfo><Number>3.5</Number></ComicInfo>")
                .number
                .as_deref(),
            Some("3.5")
        );
    }

    #[test]
    fn manga_yes_does_not_declare_a_direction_on_its_own() {
        let english =
            parsed("<ComicInfo><Manga>Yes</Manga><LanguageISO>en</LanguageISO></ComicInfo>");
        assert_eq!(english.declared_direction, None);
        assert_eq!(english.reading_direction(), ReadingDirection::LeftToRight);
        let no = parsed("<ComicInfo><Manga>No</Manga><LanguageISO>ja</LanguageISO></ComicInfo>");
        assert_eq!(no.declared_direction, Some(ReadingDirection::LeftToRight));
        assert_eq!(no.reading_direction(), ReadingDirection::LeftToRight);
        assert_eq!(
            parsed("<ComicInfo></ComicInfo>").reading_direction(),
            ReadingDirection::LeftToRight
        );
    }

    #[test]
    fn designating_page_0_as_the_cover_is_not_an_override() {
        let info =
            parsed(r#"<ComicInfo><Pages><Page Image="0" Type="FrontCover"/></Pages></ComicInfo>"#);
        assert_eq!(info.cover_page_index, None);
    }

    #[test]
    fn a_bookmark_marks_a_chapter_start_and_a_blank_one_marks_nothing() {
        let info = parsed(
            r#"<ComicInfo><Pages>
            <Page Image="0"/>
            <Page Image="12" Bookmark="Chapter Two"/>
            <Page Image="30" Bookmark="Chapter Three"/>
            <Page Image="5" Bookmark=""/>
            <Page Image="9" Bookmark="   "/>
            </Pages></ComicInfo>"#,
        );
        assert_eq!(info.chapter_start_indices, [12, 30]);
        assert_eq!(info.chapter_titles[&12], "Chapter Two");
        assert_eq!(info.chapter_titles[&30], "Chapter Three");
        assert!(
            parsed("<ComicInfo><Series>Only This</Series></ComicInfo>")
                .chapter_start_indices
                .is_empty()
        );
    }

    #[test]
    fn bytes_that_are_not_comic_info_yield_nothing() {
        assert_eq!(ComicInfo::parse(b"<Something/>"), None);
        assert_eq!(ComicInfo::parse(&[0xFF; 64]), None);
    }

    #[test]
    fn a_minimal_file_parses_and_empty_elements_are_absent() {
        let minimal = parsed("<ComicInfo><Series>Only This</Series></ComicInfo>");
        assert_eq!(minimal.series.as_deref(), Some("Only This"));
        assert_eq!(minimal.number, None);
        assert!(minimal.double_page_indices.is_empty());
        assert_eq!(
            parsed("<ComicInfo><Series>   </Series></ComicInfo>").series,
            None
        );
        assert_eq!(
            parsed("<ComicInfo><Year>MMXXVI</Year></ComicInfo>").year,
            None
        );
    }
}
