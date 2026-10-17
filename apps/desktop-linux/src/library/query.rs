//! Search, filters and sorting as a state the header bar edits and the content column
//! reads: the field stays in place, its results take over the column while text is in
//! it, and clearing it returns to the destination the reader came from
//! (`desktop-experience`, Search on a desktop).
//!
//! Search folds accents with a small Latin table until the core's collation (task 2.7)
//! lands; the sort keys are plain string order for the same reason.

use super::entry::{Format, LibraryEntry, Progress};
use super::search::Scope;

/// The sidebar destinations and filters a reader can be at.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Destination {
    #[default]
    Home,
    Library,
    Downloads,
    AllBooks,
    Series,
    RecentlyAdded,
    Downloaded,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReadState {
    Unread,
    Reading,
    Finished,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Filters {
    pub format: Option<Format>,
    pub source: Option<String>,
    pub read_state: Option<ReadState>,
    pub downloaded: Option<bool>,
}

impl Filters {
    pub fn active_count(&self) -> usize {
        usize::from(self.format.is_some())
            + usize::from(self.source.is_some())
            + usize::from(self.read_state.is_some())
            + usize::from(self.downloaded.is_some())
    }

    fn keeps(&self, entry: &LibraryEntry) -> bool {
        self.format.is_none_or(|format| entry.format == format)
            && self
                .source
                .as_deref()
                .is_none_or(|source| entry.source == source)
            && self.read_state.is_none_or(|state| {
                matches!(
                    (state, entry.progress),
                    (ReadState::Unread, Progress::Unread)
                        | (ReadState::Reading, Progress::Reading { .. })
                        | (ReadState::Finished, Progress::Finished)
                )
            })
            && self
                .downloaded
                .is_none_or(|downloaded| entry.downloaded == downloaded)
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Sort {
    #[default]
    Title,
    Series,
    DateAdded,
    LastRead,
}

impl Sort {
    pub const ALL: [Self; 4] = [Self::Title, Self::Series, Self::DateAdded, Self::LastRead];
}

/// What the header bar's field and menus hold, and where the reader was.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct QueryState {
    pub destination: Destination,
    pub text: String,
    pub filters: Filters,
    pub sort: Sort,
    /// Whether the search field was entered: the search page shows before a word is
    /// typed, with the recent searches (`navigation-shell`, What search opens onto).
    pub searching: bool,
    /// Where search looks: everything, or only what can be read now.
    pub scope: Scope,
}

impl QueryState {
    pub fn at(destination: Destination) -> Self {
        Self {
            destination,
            ..Self::default()
        }
    }

    /// Typing in the field. The destination is kept, so clearing returns to it.
    pub fn typed(&mut self, text: &str) {
        self.text = text.to_owned();
    }

    /// Escape or an emptied field: the content column returns to the destination.
    pub fn cleared(&mut self) {
        self.text.clear();
    }

    /// The field took the focus: the search page opens even before a word is typed.
    pub fn entered_search(&mut self) {
        self.searching = true;
    }

    /// Escape, or the focus left an empty field: back to the destination.
    pub fn left_search(&mut self) {
        self.searching = false;
        self.text.clear();
    }

    /// Whether the search page has taken over the content column.
    pub fn results_take_over(&self) -> bool {
        self.searching || !self.text.trim().is_empty()
    }

    /// The entries the content column shows: searched, filtered, sorted. The
    /// destination narrows first, so search scopes to where the reader is.
    pub fn apply<'a>(&self, entries: &'a [LibraryEntry]) -> Vec<&'a LibraryEntry> {
        let needle = fold(self.text.trim());
        let mut shown: Vec<&LibraryEntry> = entries
            .iter()
            .filter(|entry| self.in_destination(entry))
            .filter(|entry| self.filters.keeps(entry))
            .filter(|entry| needle.is_empty() || matches(entry, &needle))
            .collect();
        shown.sort_by(|a, b| match self.sort {
            Sort::Title => fold(&a.title).cmp(&fold(&b.title)),
            Sort::Series => (fold(a.series.as_deref().unwrap_or(&a.title)), a.issue)
                .cmp(&(fold(b.series.as_deref().unwrap_or(&b.title)), b.issue)),
            Sort::DateAdded => b.added_at.cmp(&a.added_at),
            Sort::LastRead => b.last_read_at.cmp(&a.last_read_at),
        });
        shown
    }

    fn in_destination(&self, entry: &LibraryEntry) -> bool {
        match self.destination {
            Destination::Downloads | Destination::Downloaded => entry.downloaded,
            Destination::Series => entry.series.is_some(),
            Destination::Home
            | Destination::Library
            | Destination::AllBooks
            | Destination::RecentlyAdded => true,
        }
    }
}

fn matches(entry: &LibraryEntry, needle: &str) -> bool {
    let fields = [
        Some(entry.title.as_str()),
        entry.series.as_deref(),
        entry.author.as_deref(),
    ];
    fields
        .into_iter()
        .flatten()
        .any(|field| fold(field).contains(needle))
}

/// Lower case with the common Latin accents removed, so "eric" finds "Éric".
pub fn fold(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        let base = match c {
            'à' | 'á' | 'â' | 'ã' | 'ä' | 'å' | 'À' | 'Á' | 'Â' | 'Ã' | 'Ä' | 'Å' => {
                'a'
            }
            'è' | 'é' | 'ê' | 'ë' | 'È' | 'É' | 'Ê' | 'Ë' => 'e',
            'ì' | 'í' | 'î' | 'ï' | 'Ì' | 'Í' | 'Î' | 'Ï' => 'i',
            'ò' | 'ó' | 'ô' | 'õ' | 'ö' | 'Ò' | 'Ó' | 'Ô' | 'Õ' | 'Ö' => 'o',
            'ù' | 'ú' | 'û' | 'ü' | 'Ù' | 'Ú' | 'Û' | 'Ü' => 'u',
            'ç' | 'Ç' => 'c',
            'ñ' | 'Ñ' => 'n',
            'ý' | 'ÿ' | 'Ý' => 'y',
            'ß' => {
                out.push_str("ss");
                continue;
            }
            other => other,
        };
        out.extend(base.to_lowercase());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::fixtures::corpus;

    fn titles(shown: &[&LibraryEntry]) -> Vec<String> {
        shown.iter().map(|entry| entry.title.clone()).collect()
    }

    #[test]
    fn the_field_stays_and_its_results_take_over_the_column_while_text_is_in_it() {
        let mut query = QueryState::at(Destination::Library);
        assert!(!query.results_take_over());
        query.typed("nested");
        assert!(query.results_take_over());
        assert_eq!(
            query.destination,
            Destination::Library,
            "the field keeps its place"
        );
        query.typed("   ");
        assert!(!query.results_take_over(), "whitespace is no search");
        query.typed("x");
        query.cleared();
        assert!(!query.results_take_over());
        assert_eq!(
            query.destination,
            Destination::Library,
            "clearing returns to the destination"
        );
    }

    #[test]
    fn entering_the_field_opens_search_and_leaving_it_returns_to_the_destination() {
        let mut query = QueryState::at(Destination::Library);
        query.entered_search();
        assert!(query.results_take_over(), "the page opens before a word");
        query.typed("saga");
        query.left_search();
        assert!(!query.results_take_over());
        assert!(query.text.is_empty());
        assert_eq!(query.destination, Destination::Library);
    }

    #[test]
    fn search_matches_title_series_and_author_with_accents_folded() {
        let entries = corpus();
        let mut query = QueryState::at(Destination::AllBooks);
        query.typed("eric");
        assert_eq!(titles(&query.apply(&entries)), ["Natural Sort"]);
        query.typed("FIXTURE SERIES");
        assert_eq!(
            titles(&query.apply(&entries)),
            ["Natural Sort", "Nested Chapters"]
        );
        query.typed("zoe");
        assert_eq!(titles(&query.apply(&entries)), ["Ebook Fixture"]);
        query.typed("nothing here");
        assert!(query.apply(&entries).is_empty());
        assert_eq!(fold("Çà Và ÜBER straße"), "ca va uber strasse");
    }

    #[test]
    fn the_filters_narrow_by_format_source_reading_state_and_download_state() {
        let entries = corpus();
        let mut query = QueryState::at(Destination::AllBooks);
        query.filters.format = Some(Format::Cbr);
        assert_eq!(titles(&query.apply(&entries)), ["Mislabelled Zip"]);
        query.filters = Filters {
            source: Some("Comics".into()),
            ..Filters::default()
        };
        assert_eq!(query.apply(&entries).len(), 4);
        query.filters = Filters {
            read_state: Some(ReadState::Reading),
            ..Filters::default()
        };
        assert_eq!(
            titles(&query.apply(&entries)),
            ["Ebook Fixture", "Natural Sort"]
        );
        query.filters = Filters {
            read_state: Some(ReadState::Finished),
            ..Filters::default()
        };
        assert_eq!(titles(&query.apply(&entries)), ["Nested Chapters"]);
        query.filters = Filters {
            downloaded: Some(true),
            ..Filters::default()
        };
        assert_eq!(titles(&query.apply(&entries)), ["Natural Sort"]);
        query.filters = Filters {
            read_state: Some(ReadState::Unread),
            downloaded: Some(false),
            ..Filters::default()
        };
        assert_eq!(query.filters.active_count(), 2);
        assert_eq!(
            titles(&query.apply(&entries)),
            ["Mislabelled Zip", "Seven Zip"]
        );
    }

    #[test]
    fn the_sort_keys_order_by_title_series_date_added_and_last_read() {
        let entries = corpus();
        let mut query = QueryState::at(Destination::AllBooks);
        assert_eq!(
            titles(&query.apply(&entries)),
            [
                "Ebook Fixture",
                "Mislabelled Zip",
                "Natural Sort",
                "Nested Chapters",
                "Seven Zip"
            ]
        );
        query.sort = Sort::Series;
        assert_eq!(
            titles(&query.apply(&entries)),
            [
                "Ebook Fixture",
                "Natural Sort",
                "Nested Chapters",
                "Mislabelled Zip",
                "Seven Zip"
            ]
        );
        query.sort = Sort::DateAdded;
        assert_eq!(
            titles(&query.apply(&entries))[0],
            "Seven Zip",
            "newest first"
        );
        query.sort = Sort::LastRead;
        assert_eq!(
            titles(&query.apply(&entries))[..3],
            ["Nested Chapters", "Natural Sort", "Ebook Fixture"]
        );
    }

    #[test]
    fn search_scopes_to_the_destination_the_reader_is_at() {
        let entries = corpus();
        let mut query = QueryState::at(Destination::Downloads);
        assert_eq!(titles(&query.apply(&entries)), ["Natural Sort"]);
        query.typed("fixture");
        assert_eq!(
            titles(&query.apply(&entries)),
            ["Natural Sort"],
            "scoped to downloads"
        );
        let query = QueryState::at(Destination::Series);
        assert_eq!(query.apply(&entries).len(), 2);
        let mut all = QueryState::at(Destination::AllBooks);
        all.typed("fixture");
        assert_eq!(all.apply(&entries).len(), 3, "widened to everything");
    }
}
