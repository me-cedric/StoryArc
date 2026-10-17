//! The reader's own choice of reading direction (`comic-reader`, Overriding direction):
//! it applies at once without losing the page, and it is remembered for the series, so
//! every issue of a manga a publisher tagged wrongly opens the way the reader set. A
//! publication in no series remembers it for itself. Where nothing was chosen, the
//! publication's own direction stands (the core's record: the `ComicInfo` manga flag).
//!
//! Kept in a `key=value`-style file beside the preferences, one choice per line: the
//! key, a tab, `ltr` or `rtl`. Pure, so it tests on any host.

use std::collections::BTreeMap;

use storyarc_core::domain::{Publication, ReadingDirection};
use storyarc_core::library::LibraryIndex;

/// The reader's choices, by series or by publication.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DirectionChoices {
    chosen: BTreeMap<String, ReadingDirection>,
}

/// What a choice is remembered under: the series, else the publication itself.
pub fn key_of(publication: &Publication) -> String {
    match LibraryIndex::series_name(publication) {
        Some(series) => format!("series:{series}"),
        None => format!("publication:{}", publication.id()),
    }
}

impl DirectionChoices {
    /// The direction a publication opens in: the reader's choice for its series or for
    /// itself, else its own.
    pub fn for_publication(&self, publication: &Publication) -> ReadingDirection {
        self.chosen
            .get(&key_of(publication))
            .copied()
            .unwrap_or(publication.reading_direction)
    }

    pub fn choose(&mut self, publication: &Publication, direction: ReadingDirection) {
        self.chosen.insert(key_of(publication), direction);
    }

    pub fn save(&self) -> String {
        self.chosen
            .iter()
            .map(|(key, direction)| {
                let value = match direction {
                    ReadingDirection::RightToLeft => "rtl",
                    ReadingDirection::LeftToRight => "ltr",
                };
                format!("{key}\t{value}\n")
            })
            .collect()
    }

    /// Reads the file back; a damaged line is skipped.
    pub fn restore(text: &str) -> Self {
        let chosen = text
            .lines()
            .filter_map(|line| line.rsplit_once('\t'))
            .filter_map(|(key, value)| {
                let direction = match value.trim() {
                    "rtl" => ReadingDirection::RightToLeft,
                    "ltr" => ReadingDirection::LeftToRight,
                    _ => return None,
                };
                (!key.is_empty()).then(|| (key.to_owned(), direction))
            })
            .collect();
        Self { chosen }
    }
}

#[cfg(test)]
mod tests {
    use storyarc_core::domain::{MetadataOrigin, PublicationFormat, PublicationIdentity};

    use super::*;

    fn issue(path: &str, series: Option<&str>) -> Publication {
        let mut publication = Publication::new(
            PublicationIdentity::path(path),
            PublicationFormat::Cbz,
            "Issue",
            MetadataOrigin::Inferred,
        );
        publication.series = series.map(Into::into);
        publication
    }

    #[test]
    fn a_publication_opens_in_its_own_direction_until_the_reader_chooses() {
        let mut manga = issue("/m/1.cbz", Some("Akira"));
        manga.reading_direction = ReadingDirection::RightToLeft;
        let choices = DirectionChoices::default();
        assert_eq!(
            choices.for_publication(&manga),
            ReadingDirection::RightToLeft
        );
        assert_eq!(
            choices.for_publication(&issue("/c/1.cbz", None)),
            ReadingDirection::LeftToRight
        );
    }

    #[test]
    fn a_choice_is_remembered_for_the_whole_series() {
        let first = issue("/m/1.cbz", Some("Akira"));
        let second = issue("/m/2.cbz", Some("Akira"));
        let other = issue("/m/x.cbz", Some("Saga"));
        let mut choices = DirectionChoices::default();
        choices.choose(&first, ReadingDirection::RightToLeft);
        assert_eq!(
            choices.for_publication(&second),
            ReadingDirection::RightToLeft
        );
        assert_eq!(
            choices.for_publication(&other),
            ReadingDirection::LeftToRight
        );
    }

    #[test]
    fn a_publication_in_no_series_remembers_it_for_itself() {
        let one_shot = issue("/c/one.cbz", None);
        let another = issue("/c/two.cbz", None);
        let mut choices = DirectionChoices::default();
        choices.choose(&one_shot, ReadingDirection::RightToLeft);
        assert_eq!(
            choices.for_publication(&one_shot),
            ReadingDirection::RightToLeft
        );
        assert_eq!(
            choices.for_publication(&another),
            ReadingDirection::LeftToRight
        );
    }

    #[test]
    fn the_choices_survive_a_relaunch_and_a_damaged_line_is_skipped() {
        let mut choices = DirectionChoices::default();
        choices.choose(
            &issue("/m/1.cbz", Some("Akira")),
            ReadingDirection::RightToLeft,
        );
        choices.choose(&issue("/c/1.cbz", None), ReadingDirection::LeftToRight);
        let text = choices.save();
        assert_eq!(DirectionChoices::restore(&text), choices);
        let damaged = format!("{text}nonsense\nseries:Saga\tsideways\n");
        assert_eq!(DirectionChoices::restore(&damaged), choices);
    }
}
