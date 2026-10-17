//! Home (task 2.35c, as 2.23c): the window opens on Keep reading and Up next, in that
//! order, from the core's rules. A shelf with nothing on it is absent, not a header over
//! a gap, and an empty library is a status page that offers to add a folder.

use storyarc_core::domain::Publication;
use storyarc_core::library::{LibraryIndex, ProgressIndex};

/// How many publications a Home shelf holds.
pub const SHELF_LIMIT: usize = 12;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Shelf {
    KeepReading,
    UpNext,
}

impl Shelf {
    pub fn title(self) -> (&'static str, &'static str) {
        match self {
            Self::KeepReading => ("home.keepReading", "Keep Reading"),
            Self::UpNext => ("home.upNext", "Up Next"),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Home {
    /// No publication at all: the status page.
    EmptyLibrary,
    /// The shelves that have something on them, in order. Empty when nothing was read yet.
    Shelves(Vec<(Shelf, Vec<Publication>)>),
}

impl Home {
    pub fn of(publications: &[Publication], progress: &ProgressIndex) -> Self {
        if publications.is_empty() {
            return Self::EmptyLibrary;
        }
        let shelves = [
            (
                Shelf::KeepReading,
                LibraryIndex::continue_reading(publications, SHELF_LIMIT, progress),
            ),
            (
                Shelf::UpNext,
                LibraryIndex::up_next(publications, SHELF_LIMIT, progress),
            ),
        ];
        Self::Shelves(
            shelves
                .into_iter()
                .filter(|(_, shelf)| !shelf.is_empty())
                .collect(),
        )
    }
}

#[cfg(test)]
mod tests {
    use storyarc_core::domain::{MetadataOrigin, PublicationFormat, PublicationIdentity};

    use super::*;
    use crate::library::adapter::tests::reading;

    fn issue(series: &str, number: u32) -> Publication {
        let mut publication = Publication::new(
            PublicationIdentity::path(format!("/comics/{series} {number}.cbz")),
            PublicationFormat::Cbz,
            format!("{series} {number}"),
            MetadataOrigin::Inferred,
        );
        publication.series = Some(series.to_owned());
        publication.number = Some(number.to_string());
        publication
    }

    fn titles(shelf: &[Publication]) -> Vec<&str> {
        shelf.iter().map(|p| p.display_title.as_str()).collect()
    }

    #[test]
    fn an_empty_library_is_the_status_page() {
        assert_eq!(Home::of(&[], &ProgressIndex::default()), Home::EmptyLibrary);
    }

    #[test]
    fn with_no_history_both_shelves_are_absent() {
        let library = [issue("Saga", 1), issue("Saga", 2)];
        assert_eq!(
            Home::of(&library, &ProgressIndex::default()),
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
        let finished_saga =
            reading(&library[0], 9, 10, 100).finished(true, storyarc_core::domain::Timestamp(100));
        let progress = ProgressIndex::new(vec![finished_saga, reading(&library[2], 3, 10, 200)]);
        let Home::Shelves(shelves) = Home::of(&library, &progress) else {
            panic!("a library with history has shelves");
        };
        assert_eq!(shelves.len(), 2);
        assert_eq!(shelves[0].0, Shelf::KeepReading);
        assert_eq!(titles(&shelves[0].1), ["Monstress 1"]);
        assert_eq!(shelves[1].0, Shelf::UpNext);
        assert_eq!(titles(&shelves[1].1), ["Saga 2"]);
    }

    #[test]
    fn a_shelf_with_nothing_on_it_is_absent() {
        let library = [issue("Saga", 1), issue("Saga", 2)];
        let progress = ProgressIndex::new(vec![reading(&library[0], 3, 10, 100)]);
        let Home::Shelves(shelves) = Home::of(&library, &progress) else {
            panic!("shelves");
        };
        assert_eq!(
            shelves.len(),
            1,
            "Up next offers nothing while an issue is part-read"
        );
        assert_eq!(shelves[0].0, Shelf::KeepReading);
    }
}
