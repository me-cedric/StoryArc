//! Home (task 2.35c, as 2.23c; `home-screen`): the window opens on Keep reading and Up
//! next, in that order, from the core's rules, then Recently added and Finished. A shelf
//! with nothing on it is absent, not a header over a gap, and an empty library is a
//! status page that offers to add a folder. Every shelf names how many it holds when it
//! cannot show them all, and its heading leads to the library filtered the same way.
//!
//! Pinned shelves wait for collections and reading lists (wave 3, task 3.19a).

use storyarc_core::domain::{Publication, Timestamp};
use storyarc_core::library::{LibraryIndex, ProgressIndex, ReadState as CoreReadState};

use super::query::{ReadState, Sort};

/// How many publications a Home shelf holds.
pub const SHELF_LIMIT: usize = 12;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Shelf {
    KeepReading,
    UpNext,
    RecentlyAdded,
    /// Finished since the start of this month.
    FinishedThisMonth,
    /// Finished before this month.
    FinishedEarlier,
}

impl Shelf {
    pub fn title(self) -> (&'static str, &'static str) {
        match self {
            Self::KeepReading => ("home.keepReading", "Keep Reading"),
            Self::UpNext => ("home.upNext", "Up Next"),
            Self::RecentlyAdded => ("home.recentlyAdded", "Recently added"),
            Self::FinishedThisMonth => ("home.finished.thisMonth", "Finished this month"),
            Self::FinishedEarlier => ("home.finished.earlier", "Finished earlier"),
        }
    }

    /// Where the heading leads: the library under this reading state and sort, which
    /// lists everything the shelf would show and more.
    pub fn link(self) -> (Option<ReadState>, Sort) {
        match self {
            Self::KeepReading => (Some(ReadState::Reading), Sort::LastRead),
            Self::UpNext => (Some(ReadState::Unread), Sort::Series),
            Self::RecentlyAdded => (None, Sort::DateAdded),
            Self::FinishedThisMonth | Self::FinishedEarlier => {
                (Some(ReadState::Finished), Sort::LastRead)
            }
        }
    }
}

/// One shelf: what it shows, and how many it holds in all.
#[derive(Clone, Debug, PartialEq)]
pub struct ShelfRow {
    pub shelf: Shelf,
    pub publications: Vec<Publication>,
    pub total: usize,
}

impl ShelfRow {
    fn of(shelf: Shelf, mut all: Vec<Publication>) -> Self {
        let total = all.len();
        all.truncate(SHELF_LIMIT);
        Self {
            shelf,
            publications: all,
            total,
        }
    }

    /// Whether the shelf holds more than it shows, so the heading says how many.
    pub fn is_truncated(&self) -> bool {
        self.total > self.publications.len()
    }
}

/// When the reader last looked, and now, for Recently added and Finished.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Moment {
    /// The last time the library was opened before this one; `None` on a first launch,
    /// when nothing is new to the reader yet.
    pub last_looked: Option<Timestamp>,
    pub now: Timestamp,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Home {
    /// No publication at all: the status page.
    EmptyLibrary,
    /// The shelves that have something on them, in order. Empty when nothing was read
    /// and nothing is new.
    Shelves(Vec<ShelfRow>),
}

impl Home {
    pub fn of(publications: &[Publication], progress: &ProgressIndex, moment: Moment) -> Self {
        if publications.is_empty() {
            return Self::EmptyLibrary;
        }
        let (this_month, earlier) = finished(publications, progress, moment.now);
        let shelves = [
            ShelfRow::of(
                Shelf::KeepReading,
                LibraryIndex::continue_reading(publications, usize::MAX, progress),
            ),
            ShelfRow::of(
                Shelf::UpNext,
                LibraryIndex::up_next(publications, usize::MAX, progress),
            ),
            ShelfRow::of(
                Shelf::RecentlyAdded,
                recently_added(publications, progress, moment.last_looked),
            ),
            ShelfRow::of(Shelf::FinishedThisMonth, this_month),
            ShelfRow::of(Shelf::FinishedEarlier, earlier),
        ];
        Self::Shelves(
            shelves
                .into_iter()
                .filter(|row| !row.publications.is_empty())
                .collect(),
        )
    }
}

/// Added since the reader last looked and not opened yet, newest first.
fn recently_added(
    publications: &[Publication],
    progress: &ProgressIndex,
    last_looked: Option<Timestamp>,
) -> Vec<Publication> {
    let Some(since) = last_looked else {
        return Vec::new();
    };
    let mut added: Vec<Publication> = publications
        .iter()
        .filter(|publication| publication.added_at.is_some_and(|added| added > since))
        .filter(|publication| progress.summary(publication).state == CoreReadState::Unread)
        .cloned()
        .collect();
    added.sort_by_key(|publication| std::cmp::Reverse(publication.added_at));
    added
}

/// Finished publications, most recently finished first, split at the start of the month.
fn finished(
    publications: &[Publication],
    progress: &ProgressIndex,
    now: Timestamp,
) -> (Vec<Publication>, Vec<Publication>) {
    let mut done: Vec<(Timestamp, &Publication)> = publications
        .iter()
        .filter_map(|publication| {
            let record = progress.record(publication).filter(|r| r.is_finished)?;
            Some((record.finished_at.unwrap_or(record.updated_at), publication))
        })
        .collect();
    done.sort_by(|(a, _), (b, _)| b.cmp(a));
    let month = now.start_of_month();
    let (recent, older): (Vec<_>, Vec<_>) = done.into_iter().partition(|(when, _)| *when >= month);
    let publications = |list: Vec<(Timestamp, &Publication)>| {
        list.into_iter()
            .map(|(_, publication)| publication.clone())
            .collect()
    };
    (publications(recent), publications(older))
}

#[cfg(test)]
mod tests {
    use storyarc_core::domain::{MetadataOrigin, PublicationFormat, PublicationIdentity};

    use super::*;
    use crate::library::adapter::tests::reading;

    const NOW: Timestamp = Timestamp(1_760_000_000);

    fn issue(series: &str, number: u32) -> Publication {
        let mut publication = Publication::new(
            PublicationIdentity::path(format!("/comics/{series} {number}.cbz")),
            PublicationFormat::Cbz,
            format!("{series} {number}"),
            MetadataOrigin::Inferred,
        );
        publication.series = Some(series.to_owned());
        publication.number = Some(number.to_string());
        publication.added_at = Some(Timestamp(1));
        publication
    }

    fn titles(shelf: &[Publication]) -> Vec<&str> {
        shelf.iter().map(|p| p.display_title.as_str()).collect()
    }

    fn first_launch() -> Moment {
        Moment {
            last_looked: None,
            now: NOW,
        }
    }

    fn shelves(home: Home) -> Vec<ShelfRow> {
        match home {
            Home::Shelves(shelves) => shelves,
            Home::EmptyLibrary => panic!("a library with publications has shelves"),
        }
    }

    #[test]
    fn an_empty_library_is_the_status_page() {
        assert_eq!(
            Home::of(&[], &ProgressIndex::default(), first_launch()),
            Home::EmptyLibrary
        );
    }

    #[test]
    fn with_no_history_both_shelves_are_absent() {
        let library = [issue("Saga", 1), issue("Saga", 2)];
        assert_eq!(
            Home::of(&library, &ProgressIndex::default(), first_launch()),
            Home::Shelves(Vec::new())
        );
    }

    #[test]
    fn keep_reading_comes_first_and_up_next_offers_the_next_issue() {
        let library = [
            issue("Saga", 1),
            issue("Saga", 2),
            issue("Monstress", 1),
            issue("Monstress", 2),
        ];
        let finished_saga = reading(&library[0], 9, 10, 100).finished(true, Timestamp(100));
        let progress = ProgressIndex::new(vec![finished_saga, reading(&library[2], 3, 10, 200)]);
        let shelves = shelves(Home::of(&library, &progress, first_launch()));
        assert_eq!(shelves[0].shelf, Shelf::KeepReading);
        assert_eq!(titles(&shelves[0].publications), ["Monstress 1"]);
        assert_eq!(shelves[1].shelf, Shelf::UpNext);
        assert_eq!(titles(&shelves[1].publications), ["Saga 2"]);
        assert_eq!(
            shelves[2].shelf,
            Shelf::FinishedEarlier,
            "Finished comes last"
        );
        assert_eq!(titles(&shelves[2].publications), ["Saga 1"]);
    }

    #[test]
    fn a_shelf_with_nothing_on_it_is_absent() {
        let library = [issue("Saga", 1), issue("Saga", 2)];
        let progress = ProgressIndex::new(vec![reading(&library[0], 3, 10, 100)]);
        let shelves = shelves(Home::of(&library, &progress, first_launch()));
        assert_eq!(
            shelves.len(),
            1,
            "Up next offers nothing while an issue is part-read"
        );
        assert_eq!(shelves[0].shelf, Shelf::KeepReading);
    }

    #[test]
    fn recently_added_holds_what_arrived_since_the_reader_last_looked_newest_first() {
        let mut library = vec![issue("Saga", 1), issue("Saga", 2), issue("Saga", 3)];
        library[1].added_at = Some(Timestamp(500));
        library[2].added_at = Some(Timestamp(900));
        let looked = Moment {
            last_looked: Some(Timestamp(400)),
            now: NOW,
        };
        let shelves = shelves(Home::of(&library, &ProgressIndex::default(), looked));
        assert_eq!(shelves[0].shelf, Shelf::RecentlyAdded);
        assert_eq!(titles(&shelves[0].publications), ["Saga 3", "Saga 2"]);
        let first = Home::of(&library, &ProgressIndex::default(), first_launch());
        assert_eq!(
            first,
            Home::Shelves(Vec::new()),
            "nothing is new on a first launch"
        );
    }

    #[test]
    fn finished_comes_last_grouped_by_when_it_was_finished() {
        let library = [issue("A", 1), issue("B", 1), issue("C", 1)];
        let this_month = NOW.start_of_month();
        let progress = ProgressIndex::new(vec![
            reading(&library[0], 9, 10, 10).finished(true, Timestamp(this_month.0 + 60)),
            reading(&library[1], 9, 10, 10).finished(true, Timestamp(this_month.0 - 60)),
            reading(&library[2], 9, 10, 10).finished(true, Timestamp(this_month.0 + 120)),
        ]);
        let shelves = shelves(Home::of(&library, &progress, first_launch()));
        let kinds: Vec<Shelf> = shelves.iter().map(|row| row.shelf).collect();
        assert_eq!(kinds, [Shelf::FinishedThisMonth, Shelf::FinishedEarlier]);
        assert_eq!(titles(&shelves[0].publications), ["C 1", "A 1"]);
        assert_eq!(titles(&shelves[1].publications), ["B 1"]);
    }

    #[test]
    fn a_shelf_that_holds_more_than_it_shows_says_how_many_and_leads_to_the_library() {
        let library: Vec<Publication> = (1..=20).map(|n| issue(&format!("S{n}"), 1)).collect();
        let progress = ProgressIndex::new(
            library
                .iter()
                .enumerate()
                .map(|(at, p)| reading(p, 2, 10, at as i64))
                .collect(),
        );
        let shelves = shelves(Home::of(&library, &progress, first_launch()));
        assert_eq!(shelves[0].publications.len(), SHELF_LIMIT);
        assert_eq!(shelves[0].total, 20);
        assert!(shelves[0].is_truncated());
        assert_eq!(
            Shelf::KeepReading.link(),
            (Some(ReadState::Reading), Sort::LastRead)
        );
        assert_eq!(Shelf::RecentlyAdded.link(), (None, Sort::DateAdded));
    }
}
