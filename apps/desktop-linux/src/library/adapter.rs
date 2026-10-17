//! The library's view-models over the core's records (tasks 2.35a and 2.35b): a cell's
//! entry from a `storyarc_core` publication and its progress, and the header bar's
//! query state handed to `LibraryIndex::arrange`, so search, filters and sorting are
//! the core's rules of task 2.8a under the reader's collation.

use storyarc_core::domain::{Publication, PublicationFormat};
use storyarc_core::library::{
    DownloadFilter, LibraryIndex, LibraryQuery, LibrarySort, ProgressIndex, ProgressSummary,
    ReadState as CoreReadState,
};
use storyarc_core::locale::Collation;

use super::entry::{Cover, Format, LibraryEntry, Progress};
use super::query::{Destination, QueryState, ReadState, Sort};

impl Format {
    pub fn of(format: PublicationFormat) -> Self {
        match format {
            PublicationFormat::Cbz => Self::Cbz,
            PublicationFormat::Cbr => Self::Cbr,
            PublicationFormat::Cbt => Self::Cbt,
            PublicationFormat::Cb7 => Self::Cb7,
            PublicationFormat::Epub => Self::Epub,
            PublicationFormat::Pdf => Self::Pdf,
            PublicationFormat::ImageFolder => Self::Folder,
            PublicationFormat::M4b
            | PublicationFormat::Mp3
            | PublicationFormat::Flac
            | PublicationFormat::Ogg
            | PublicationFormat::AudioFolder => Self::Audiobook,
        }
    }

    /// The core's formats this filter keeps.
    pub fn core_formats(self) -> Vec<PublicationFormat> {
        PublicationFormat::ALL
            .into_iter()
            .filter(|format| Self::of(*format) == self)
            .collect()
    }
}

impl Progress {
    /// The cell's progress from the core's summary, in whole percent.
    pub fn of(summary: ProgressSummary) -> Self {
        match summary.state {
            CoreReadState::Unread => Self::Unread,
            CoreReadState::Finished => Self::Finished,
            CoreReadState::InProgress => Self::Reading {
                index: (summary.fraction.clamp(0.0, 1.0) * 100.0).round() as u32,
                of: 100,
            },
        }
    }
}

fn seconds(timestamp: Option<storyarc_core::domain::Timestamp>) -> Option<u64> {
    timestamp.map(|moment| u64::try_from(moment.0).unwrap_or(0))
}

impl LibraryEntry {
    /// A cell for a publication the core indexed.
    pub fn from_core(publication: &Publication, summary: ProgressSummary, source: &str) -> Self {
        Self {
            id: publication.id(),
            title: publication.display_title.clone(),
            series: publication.series.clone(),
            issue: publication
                .number
                .as_deref()
                .and_then(|number| number.trim().parse().ok()),
            author: publication.authors.first().cloned(),
            format: Format::of(publication.format),
            source: source.to_owned(),
            page_count: publication
                .page_count
                .map_or(0, |count| u32::try_from(count).unwrap_or(u32::MAX)),
            progress: Progress::of(summary),
            downloaded: false,
            added_at: seconds(publication.added_at).unwrap_or(0),
            last_read_at: seconds(summary.last_read_at),
            cover: Cover::Placeholder,
            cannot_open: None,
        }
    }

    /// The entry for a file the scan found and could not open, with its reason.
    pub fn could_not_open(name: &str, reason: &str, source: &str) -> Self {
        Self {
            id: format!("skipped:{source}/{name}"),
            title: name.to_owned(),
            series: None,
            issue: None,
            author: None,
            format: Format::Cbz,
            source: source.to_owned(),
            page_count: 0,
            progress: Progress::Unread,
            downloaded: false,
            added_at: 0,
            last_read_at: None,
            cover: Cover::Placeholder,
            cannot_open: Some(reason.to_owned()),
        }
    }
}

impl QueryState {
    /// The header bar's state as the core's query. The source filter is the Linux side's,
    /// because a folder library is known by its folder, not by a source id.
    pub fn to_core(&self) -> LibraryQuery {
        let sort = match (self.destination, self.sort) {
            (Destination::RecentlyAdded, _) | (_, Sort::DateAdded) => LibrarySort::DateAdded,
            (_, Sort::Title) => LibrarySort::Title,
            (_, Sort::Series) => LibrarySort::Series,
            (_, Sort::LastRead) => LibrarySort::LastRead,
        };
        LibraryQuery {
            search: self.text.trim().to_owned(),
            formats: self
                .filters
                .format
                .map(Format::core_formats)
                .unwrap_or_default(),
            read_states: self
                .filters
                .read_state
                .map(|state| match state {
                    ReadState::Unread => CoreReadState::Unread,
                    ReadState::Reading => CoreReadState::InProgress,
                    ReadState::Finished => CoreReadState::Finished,
                })
                .into_iter()
                .collect(),
            downloads: match self.filters.downloaded {
                None => DownloadFilter::Either,
                Some(true) => DownloadFilter::Downloaded,
                Some(false) => DownloadFilter::NotDownloaded,
            },
            sort,
            ..LibraryQuery::default()
        }
    }

    /// The publications the content column shows, in order: the core's search, filters
    /// and sort, then the destination and the folder the reader narrowed to.
    /// `source_of` names a publication's folder. Nothing local is a download.
    pub fn arrange(
        &self,
        publications: &[Publication],
        progress: &ProgressIndex,
        collation: &Collation,
        source_of: impl Fn(&Publication) -> Option<String>,
    ) -> Vec<Publication> {
        LibraryIndex::arrange(publications, &self.to_core(), collation, progress, |_| {
            false
        })
        .into_iter()
        .filter(|publication| match self.destination {
            Destination::Downloads | Destination::Downloaded => false,
            Destination::Series => publication.series.is_some(),
            _ => true,
        })
        .filter(|publication| {
            self.filters
                .source
                .as_deref()
                .is_none_or(|source| source_of(publication).as_deref() == Some(source))
        })
        .collect()
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use std::path::Path;

    use storyarc_core::domain::{PublicationIdentity, ReadingPosition, ReadingProgress, Timestamp};
    use storyarc_core::io::CancelToken;
    use storyarc_core::library::FolderSource;

    use super::*;
    use crate::library::query::Filters;

    /// The shared corpus, scanned by the core as a folder library would be.
    pub fn fixture_library() -> FolderSource {
        let root =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../packages/test-fixtures/comics");
        FolderSource::open(root, &CancelToken::new()).expect("the fixture folder scans")
    }

    pub fn reading(publication: &Publication, index: i64, of: i64, at: i64) -> ReadingProgress {
        ReadingProgress::new(
            publication.identity.clone(),
            ReadingPosition::page(index, of),
            Timestamp(at),
        )
    }

    fn titles(publications: &[Publication]) -> Vec<String> {
        publications
            .iter()
            .map(|p| p.display_title.clone())
            .collect()
    }

    fn named<'a>(publications: &'a [Publication], fragment: &str) -> &'a Publication {
        publications
            .iter()
            .find(|p| p.display_title.to_lowercase().contains(fragment))
            .unwrap_or_else(|| panic!("no fixture titled like {fragment}"))
    }

    #[test]
    fn every_fixture_comic_becomes_a_cell_and_the_cb7_is_named_as_skipped() {
        let library = fixture_library();
        assert!(library.publications().len() > 10);
        let entries: Vec<LibraryEntry> = library
            .publications()
            .iter()
            .map(|p| LibraryEntry::from_core(p, ProgressSummary::UNREAD, "comics"))
            .collect();
        assert!(entries.iter().all(|entry| !entry.title.is_empty()));
        assert!(entries.iter().all(|entry| entry.cannot_open.is_none()));
        assert!(
            library
                .skipped()
                .iter()
                .any(|file| file.path.ends_with("refused.cb7")),
            "{:?}",
            library.skipped()
        );
        let skipped = LibraryEntry::could_not_open("refused.cb7", "CB7 is not supported", "comics");
        assert_eq!(skipped.cell_label_key(), Some("CB7 is not supported"));
        assert!(
            skipped
                .accessible_description()
                .contains("cannot be opened")
        );
    }

    #[test]
    fn search_finds_by_title_through_the_core_and_clearing_shows_everything() {
        let library = fixture_library();
        let collation = Collation::new("en");
        let progress = ProgressIndex::default();
        let mut state = QueryState::at(Destination::Library);
        let all = state.arrange(library.publications(), &progress, &collation, |_| None);
        assert_eq!(all.len(), library.publications().len());
        state.typed("nested");
        let found = state.arrange(library.publications(), &progress, &collation, |_| None);
        assert!(!found.is_empty());
        assert!(
            found
                .iter()
                .all(|p| p.display_title.to_lowercase().contains("nested"))
        );
        state.cleared();
        let back = state.arrange(library.publications(), &progress, &collation, |_| None);
        assert_eq!(back.len(), all.len());
    }

    #[test]
    fn the_filters_narrow_by_format_reading_state_and_folder() {
        let library = fixture_library();
        let publications = library.publications();
        let collation = Collation::new("en");
        let started = named(publications, "natural");
        let progress = ProgressIndex::new(vec![reading(started, 2, 10, 100)]);
        let mut state = QueryState::at(Destination::Library);
        state.filters.format = Some(Format::Cbr);
        let rar = state.arrange(publications, &progress, &collation, |_| None);
        assert!(!rar.is_empty());
        assert!(rar.iter().all(|p| p.format == PublicationFormat::Cbr));
        state.filters = Filters {
            read_state: Some(ReadState::Reading),
            ..Filters::default()
        };
        let reading_now = state.arrange(publications, &progress, &collation, |_| None);
        assert_eq!(titles(&reading_now), vec![started.display_title.clone()]);
        state.filters = Filters {
            source: Some("Elsewhere".into()),
            ..Filters::default()
        };
        let elsewhere = state.arrange(publications, &progress, &collation, |_| {
            Some("comics".into())
        });
        assert!(elsewhere.is_empty());
        state.filters = Filters {
            downloaded: Some(true),
            ..Filters::default()
        };
        assert!(
            state
                .arrange(publications, &progress, &collation, |_| None)
                .is_empty()
        );
    }

    #[test]
    fn the_sort_keys_reach_the_core_and_titles_follow_the_collation() {
        let mut state = QueryState::at(Destination::Library);
        assert_eq!(state.to_core().sort, LibrarySort::Title);
        state.sort = Sort::LastRead;
        assert_eq!(state.to_core().sort, LibrarySort::LastRead);
        state.sort = Sort::Series;
        assert_eq!(state.to_core().sort, LibrarySort::Series);
        assert_eq!(
            QueryState::at(Destination::RecentlyAdded).to_core().sort,
            LibrarySort::DateAdded
        );
        let library = fixture_library();
        let collation = Collation::new("en");
        let sorted = QueryState::at(Destination::Library).arrange(
            library.publications(),
            &ProgressIndex::default(),
            &collation,
            |_| None,
        );
        let titles = titles(&sorted);
        assert!(
            titles
                .windows(2)
                .all(|pair| collation.compare_titles(&pair[0], &pair[1]).is_le())
        );
    }

    #[test]
    fn a_core_summary_becomes_the_cell_progress() {
        let p = Publication::new(
            PublicationIdentity::path("/a.cbz"),
            PublicationFormat::ImageFolder,
            "A",
            storyarc_core::domain::MetadataOrigin::Inferred,
        );
        let entry = LibraryEntry::from_core(&p, ProgressSummary::UNREAD, "comics");
        assert_eq!(entry.format, Format::Folder);
        assert_eq!(entry.progress, Progress::Unread);
        let half = ProgressSummary::of(Some(&reading(&p, 5, 11, 7)));
        assert_eq!(Progress::of(half).percent(), 50);
        assert_eq!(Format::Audiobook.core_formats().len(), 5);
    }
}
