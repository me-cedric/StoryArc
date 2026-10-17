//! Turning the whole library into the list on screen (task 2.8a of `desktop-clients`).
//! Mirrored from StoryArcKit's `LibraryIndex`, `LibraryQuery`, `LibraryScope`,
//! `DownloadFilter` and `HomeShelves.upNext`; Android's `LibraryIndex` is the same rules.
//!
//! Pure: no store, no clock, no network. The caller hands over the publications, the
//! reader's collation and the progress records, and gets back an ordered list. Search here
//! is folded for accents as well as case (`locale::fold`); the phones' `LibraryIndex.rank`
//! lower-cases only, which is the one place this mirror goes further than its source.

use std::cmp::Ordering;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Deserializer, Serialize};

use crate::domain::{
    NaturalOrder, Publication, PublicationFormat, PublicationStatus, ReadingProgress, Timestamp,
};
use crate::locale::{Collation, fold};

/// How far through a publication the reader got, as the library thinks of it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ReadState {
    Unread,
    InProgress,
    Finished,
}

/// What the library is ordered by. Dates, sizes and progress run newest, largest and
/// furthest first; titles and series run A to Z. `ascending: false` reverses either.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LibrarySort {
    #[default]
    Title,
    Series,
    LastRead,
    Progress,
    Year,
    DateAdded,
    FileSize,
}

/// The years a publication may have been released in. Either end may be absent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct YearRange {
    pub from: Option<i64>,
    pub to: Option<i64>,
}

impl YearRange {
    /// Whether the range narrows anything. One bound is enough.
    pub fn is_active(&self) -> bool {
        self.from.is_some() || self.to.is_some()
    }

    /// Whether a year falls inside. A publication with no year is *outside* an active
    /// range, not before everything.
    pub fn contains(&self, year: Option<i64>) -> bool {
        if !self.is_active() {
            return true;
        }
        let Some(year) = year else { return false };
        self.from.is_none_or(|from| year >= from) && self.to.is_none_or(|to| year <= to)
    }
}

/// Which library is being shown. A filter on the listing that stands down for a search:
/// "search still covers the whole library" (`library-browsing`).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LibraryScope {
    #[default]
    AllSources,
    Source(String),
}

impl LibraryScope {
    pub fn contains(&self, publication: &Publication) -> bool {
        match self {
            Self::AllSources => true,
            Self::Source(id) => publication.source_id.as_deref() == Some(id.as_str()),
        }
    }
}

/// Whether the shelf keeps what the app downloaded, what it did not, or both.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DownloadFilter {
    #[default]
    Either,
    Downloaded,
    NotDownloaded,
}

impl DownloadFilter {
    /// Whether the group is narrowing anything.
    pub fn is_active(self) -> bool {
        self != Self::Either
    }

    pub fn keeps(self, is_downloaded: bool) -> bool {
        match self {
            Self::Either => true,
            Self::Downloaded => is_downloaded,
            Self::NotDownloaded => !is_downloaded,
        }
    }
}

/// What the reader is looking at, and in what order. One value, so "return to the library
/// and the filters are still applied" is one thing to keep.
///
/// Every field reads back on its own: a query an older build wrote, or one naming a format
/// this build does not know, keeps everything it can rather than falling back to nothing.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LibraryQuery {
    pub search: String,
    #[serde(deserialize_with = "lenient_list")]
    pub read_states: Vec<ReadState>,
    #[serde(deserialize_with = "lenient_list")]
    pub formats: Vec<PublicationFormat>,
    pub languages: Vec<String>,
    /// Publishers as the publication spells them, not normalised.
    pub publishers: Vec<String>,
    pub genres: Vec<String>,
    pub tags: Vec<String>,
    #[serde(deserialize_with = "lenient_list")]
    pub statuses: Vec<PublicationStatus>,
    pub years: YearRange,
    #[serde(deserialize_with = "lenient_value")]
    pub sort: LibrarySort,
    pub ascending: bool,
    #[serde(deserialize_with = "lenient_value")]
    pub scope: LibraryScope,
    #[serde(deserialize_with = "lenient_value")]
    pub downloads: DownloadFilter,
}

impl Default for LibraryQuery {
    fn default() -> Self {
        Self {
            search: String::new(),
            read_states: Vec::new(),
            formats: Vec::new(),
            languages: Vec::new(),
            publishers: Vec::new(),
            genres: Vec::new(),
            tags: Vec::new(),
            statuses: Vec::new(),
            years: YearRange::default(),
            sort: LibrarySort::Title,
            ascending: true,
            scope: LibraryScope::AllSources,
            downloads: DownloadFilter::Either,
        }
    }
}

impl LibraryQuery {
    /// What the filter control shows as a badge: a group counts once however many values
    /// it holds, and the year range once for both its ends.
    pub fn active_filter_count(&self) -> usize {
        [
            !self.read_states.is_empty(),
            !self.formats.is_empty(),
            !self.languages.is_empty(),
            !self.publishers.is_empty(),
            !self.genres.is_empty(),
            !self.tags.is_empty(),
            !self.statuses.is_empty(),
            self.years.is_active(),
            self.downloads.is_active(),
        ]
        .into_iter()
        .filter(|active| *active)
        .count()
    }

    pub fn has_filters(&self) -> bool {
        self.active_filter_count() > 0
    }

    /// Whether anything at all narrows the view, search included. Not the scope: a scoped
    /// library is still a library to continue reading in.
    pub fn is_narrowed(&self) -> bool {
        self.has_filters() || !self.search.trim().is_empty()
    }

    /// Every filter off, the search, the sort and the scope untouched.
    pub fn without_filters(&self) -> Self {
        Self {
            read_states: Vec::new(),
            formats: Vec::new(),
            languages: Vec::new(),
            publishers: Vec::new(),
            genres: Vec::new(),
            tags: Vec::new(),
            statuses: Vec::new(),
            years: YearRange::default(),
            downloads: DownloadFilter::Either,
            ..self.clone()
        }
    }
}

/// A list whose unreadable entries are dropped rather than failing the whole value.
fn lenient_list<'de, D: Deserializer<'de>, T: DeserializeOwned>(
    deserializer: D,
) -> Result<Vec<T>, D::Error> {
    let raw = Vec::<serde_json::Value>::deserialize(deserializer)?;
    Ok(raw
        .into_iter()
        .filter_map(|value| serde_json::from_value(value).ok())
        .collect())
}

/// A value that falls back to its default when it cannot be read.
fn lenient_value<'de, D: Deserializer<'de>, T: DeserializeOwned + Default>(
    deserializer: D,
) -> Result<T, D::Error> {
    let raw = serde_json::Value::deserialize(deserializer)?;
    Ok(serde_json::from_value(raw).unwrap_or_default())
}

/// What the library knows about one publication's progress.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ProgressSummary {
    pub state: ReadState,
    /// 0 to 1; 1 when finished.
    pub fraction: f64,
    pub last_read_at: Option<Timestamp>,
}

impl ProgressSummary {
    pub const UNREAD: Self = Self {
        state: ReadState::Unread,
        fraction: 0.0,
        last_read_at: None,
    };

    /// The summary of a record, or of none. Opened and never moved is still unread.
    pub fn of(record: Option<&ReadingProgress>) -> Self {
        let Some(record) = record else {
            return Self::UNREAD;
        };
        let fraction = if record.is_finished {
            1.0
        } else {
            record.position.fraction()
        };
        let state = if record.is_finished {
            ReadState::Finished
        } else if fraction > 0.0 {
            ReadState::InProgress
        } else {
            ReadState::Unread
        };
        Self {
            state,
            fraction,
            last_read_at: Some(record.updated_at),
        }
    }
}

/// The progress records, found by publication. A record belongs to a publication when any
/// identity component matches (ADR-0006); when several do, the most recent wins.
#[derive(Debug, Clone, Default)]
pub struct ProgressIndex {
    records: Vec<ReadingProgress>,
}

impl ProgressIndex {
    pub fn new(records: Vec<ReadingProgress>) -> Self {
        Self { records }
    }

    pub fn records(&self) -> &[ReadingProgress] {
        &self.records
    }

    /// The record for a publication, if any.
    pub fn record(&self, publication: &Publication) -> Option<&ReadingProgress> {
        self.records
            .iter()
            .filter(|record| record.identity.matches(&publication.identity))
            .max_by_key(|record| record.updated_at)
    }

    pub fn summary(&self, publication: &Publication) -> ProgressSummary {
        ProgressSummary::of(self.record(publication))
    }
}

/// The browsing rules. Stateless; every function takes what it reads.
pub struct LibraryIndex;

impl LibraryIndex {
    /// The filtered, ranked and sorted list.
    ///
    /// While a search runs, how well a publication matches decides first and the sort breaks
    /// ties; the scope stands down so the search covers the whole library. `is_downloaded`
    /// answers the download filter.
    pub fn arrange(
        publications: &[Publication],
        query: &LibraryQuery,
        collation: &Collation,
        progress: &ProgressIndex,
        is_downloaded: impl Fn(&Publication) -> bool,
    ) -> Vec<Publication> {
        let term = fold(&query.search);
        let mut kept: Vec<(Option<u8>, ProgressSummary, &Publication)> = publications
            .iter()
            .filter(|publication| !term.is_empty() || query.scope.contains(publication))
            .map(|publication| {
                let rank = Self::rank(publication, &term);
                (rank, progress.summary(publication), publication)
            })
            .filter(|(rank, summary, publication)| {
                Self::keeps(publication, query, summary.state)
                    && query.downloads.keeps(is_downloaded(publication))
                    && (term.is_empty() || rank.is_some())
            })
            .collect();
        kept.sort_by(
            |(left_rank, left_progress, left), (right_rank, right_progress, right)| {
                let by_rank = if term.is_empty() {
                    Ordering::Equal
                } else {
                    left_rank.cmp(right_rank)
                };
                by_rank
                    .then_with(|| {
                        let by_field = Self::compare(
                            left,
                            right,
                            query.sort,
                            collation,
                            (left_progress, right_progress),
                        );
                        if query.ascending {
                            by_field
                        } else {
                            by_field.reverse()
                        }
                    })
                    // A stable tiebreak, always ascending: a list that reshuffles equal rows when
                    // the direction flips looks broken.
                    .then_with(|| {
                        collation.compare_titles(&left.display_title, &right.display_title)
                    })
                    .then_with(|| left.display_title.cmp(&right.display_title))
                    .then_with(|| left.id().cmp(&right.id()))
            },
        );
        kept.into_iter()
            .map(|(_, _, publication)| publication.clone())
            .collect()
    }

    /// In-progress publications, most recently read first. Empty, not a header over a gap,
    /// when nothing is in progress.
    pub fn continue_reading(
        publications: &[Publication],
        limit: usize,
        progress: &ProgressIndex,
    ) -> Vec<Publication> {
        let mut reading: Vec<(ProgressSummary, &Publication)> = publications
            .iter()
            .map(|publication| (progress.summary(publication), publication))
            .filter(|(summary, _)| summary.state == ReadState::InProgress)
            .collect();
        reading.sort_by(|(left, left_pub), (right, right_pub)| {
            right
                .last_read_at
                .cmp(&left.last_read_at)
                .then_with(|| left_pub.display_title.cmp(&right_pub.display_title))
        });
        reading
            .into_iter()
            .take(limit)
            .map(|(_, publication)| publication.clone())
            .collect()
    }

    /// The next unread issue of each series the reader has started, most recently read
    /// series first (`home-screen`, *Up next*). A series with something part-read offers
    /// nothing (Keep reading has it), and so do a series with nothing finished and one read
    /// to the end. A gap in a collection is not re-offered.
    pub fn up_next(
        publications: &[Publication],
        limit: usize,
        progress: &ProgressIndex,
    ) -> Vec<Publication> {
        let mut series: Vec<&str> = publications
            .iter()
            .filter_map(|publication| publication.series.as_deref())
            .collect();
        series.sort_unstable();
        series.dedup();
        let state = |publication: &Publication| progress.summary(publication).state;
        let mut offered: Vec<(Publication, Timestamp)> = series
            .into_iter()
            .filter_map(|name| {
                let issues: Vec<Publication> = publications
                    .iter()
                    .filter(|publication| publication.series.as_deref() == Some(name))
                    .cloned()
                    .collect();
                if issues
                    .iter()
                    .any(|issue| state(issue) == ReadState::InProgress)
                {
                    return None;
                }
                let finished: Vec<Publication> = issues
                    .iter()
                    .filter(|issue| progress.record(issue).is_some_and(|r| r.is_finished))
                    .cloned()
                    .collect();
                // The finished issue no other finished issue follows: the furthest read.
                let furthest = finished
                    .iter()
                    .find(|issue| Self::next(issue, &finished).is_none())?;
                let candidate = Self::next(furthest, &issues)?;
                if state(candidate) != ReadState::Unread {
                    return None;
                }
                let when = progress
                    .record(furthest)
                    .map_or(Timestamp(i64::MIN), |record| record.updated_at);
                Some((candidate.clone(), when))
            })
            .collect();
        offered.sort_by(|(left, left_when), (right, right_when)| {
            right_when
                .cmp(left_when)
                .then_with(|| left.display_title.cmp(&right.display_title))
        });
        offered
            .into_iter()
            .take(limit)
            .map(|(publication, _)| publication)
            .collect()
    }

    /// The next openable publication in the same series by issue number, or `None`.
    pub fn next<'a>(
        publication: &Publication,
        library: &'a [Publication],
    ) -> Option<&'a Publication> {
        let series = publication.series.as_ref()?;
        let current = Self::issue_number(publication);
        library
            .iter()
            .filter(|candidate| {
                candidate.id() != publication.id()
                    && candidate.series.as_ref() == Some(series)
                    && candidate.is_openable()
                    && Self::issue_number(candidate) > current
            })
            .min_by(|a, b| Self::issue_number(a).total_cmp(&Self::issue_number(b)))
    }

    /// The openable publication before this one in the same series, or `None`.
    pub fn previous<'a>(
        publication: &Publication,
        library: &'a [Publication],
    ) -> Option<&'a Publication> {
        let series = publication.series.as_ref()?;
        let current = Self::issue_number(publication);
        library
            .iter()
            .filter(|candidate| {
                candidate.id() != publication.id()
                    && candidate.series.as_ref() == Some(series)
                    && candidate.is_openable()
                    && Self::issue_number(candidate) < current
            })
            .max_by(|a, b| Self::issue_number(a).total_cmp(&Self::issue_number(b)))
    }

    /// The series a publication actually names: blank and whitespace are none.
    pub fn series_name(publication: &Publication) -> Option<&str> {
        publication
            .series
            .as_deref()
            .map(str::trim)
            .filter(|name| !name.is_empty())
    }

    /// An issue number as a number, so #10 follows #9; a publication with none sorts last.
    fn issue_number(publication: &Publication) -> f64 {
        publication
            .number
            .as_deref()
            .and_then(|raw| {
                raw.chars()
                    .filter(|c| c.is_ascii_digit() || *c == '.')
                    .collect::<String>()
                    .parse::<f64>()
                    .ok()
            })
            .unwrap_or(f64::MAX)
    }

    /// Whether a publication survives every filter group: groups combine with AND, the
    /// values inside one group with OR, and an empty group has no opinion.
    fn keeps(publication: &Publication, query: &LibraryQuery, state: ReadState) -> bool {
        let holds = |chosen: &[String], value: &Option<String>| {
            chosen.is_empty() || value.as_ref().is_some_and(|value| chosen.contains(value))
        };
        let meets = |chosen: &[String], values: &[String]| {
            chosen.is_empty() || values.iter().any(|value| chosen.contains(value))
        };
        (query.read_states.is_empty() || query.read_states.contains(&state))
            && (query.formats.is_empty() || query.formats.contains(&publication.format))
            && holds(&query.languages, &publication.language)
            && holds(&query.publishers, &publication.publisher)
            && meets(&query.genres, &publication.genres)
            && meets(&query.tags, &publication.tags)
            && (query.statuses.is_empty()
                || publication
                    .status
                    .is_some_and(|status| query.statuses.contains(&status)))
            && query.years.contains(publication.year)
    }

    /// How well a publication answers a folded term, lower being better, or `None`. A title
    /// that starts with the term is what the reader meant far more often than an author
    /// whose name contains it.
    fn rank(publication: &Publication, term: &str) -> Option<u8> {
        if term.is_empty() {
            return None;
        }
        let has = |value: &str| fold(value).contains(term);
        let title = fold(&publication.display_title);
        if title.starts_with(term) {
            return Some(0);
        }
        if title.contains(term) {
            return Some(1);
        }
        if publication.series.as_deref().is_some_and(has) {
            return Some(2);
        }
        if publication.authors.iter().any(|author| has(author)) {
            return Some(3);
        }
        if publication.publisher.as_deref().is_some_and(has)
            || publication.genres.iter().any(|genre| has(genre))
            || publication.tags.iter().any(|tag| has(tag))
        {
            return Some(4);
        }
        None
    }

    fn compare(
        left: &Publication,
        right: &Publication,
        sort: LibrarySort,
        collation: &Collation,
        (left_progress, right_progress): (&ProgressSummary, &ProgressSummary),
    ) -> Ordering {
        match sort {
            LibrarySort::Title => {
                collation.compare_titles(&left.display_title, &right.display_title)
            }
            LibrarySort::Series => Self::compare_by_series(left, right, collation),
            // Never read sorts last whichever way: a row with no date is not the oldest.
            LibrarySort::LastRead => right_progress
                .last_read_at
                .unwrap_or(Timestamp(i64::MIN))
                .cmp(&left_progress.last_read_at.unwrap_or(Timestamp(i64::MIN))),
            LibrarySort::Progress => right_progress.fraction.total_cmp(&left_progress.fraction),
            LibrarySort::Year => right.year.unwrap_or(0).cmp(&left.year.unwrap_or(0)),
            LibrarySort::DateAdded => right
                .added_at
                .unwrap_or(Timestamp(i64::MIN))
                .cmp(&left.added_at.unwrap_or(Timestamp(i64::MIN))),
            LibrarySort::FileSize => right
                .file_size
                .unwrap_or(0)
                .cmp(&left.file_size.unwrap_or(0)),
        }
    }

    /// Every series first in name order, then everything that names none as one pile.
    /// Within a series the issue number decides, then the file's natural order.
    fn compare_by_series(
        left: &Publication,
        right: &Publication,
        collation: &Collation,
    ) -> Ordering {
        match (Self::series_name(left), Self::series_name(right)) {
            (None, None) => collation.compare_titles(&left.display_title, &right.display_title),
            (None, Some(_)) => Ordering::Greater,
            (Some(_), None) => Ordering::Less,
            (Some(left_series), Some(right_series)) => collation
                .compare_titles(left_series, right_series)
                .then_with(|| Self::issue_number(left).total_cmp(&Self::issue_number(right)))
                .then_with(|| match (file_name(left), file_name(right)) {
                    (Some(left_file), Some(right_file)) => {
                        NaturalOrder::compare(left_file, right_file)
                    }
                    _ => collation.compare_titles(&left.display_title, &right.display_title),
                }),
        }
    }
}

/// The file a publication was read from, or `None` for a server's chapter.
fn file_name(publication: &Publication) -> Option<&str> {
    publication
        .identity
        .normalized_path
        .as_deref()?
        .rsplit('/')
        .find(|part| !part.is_empty())
}
