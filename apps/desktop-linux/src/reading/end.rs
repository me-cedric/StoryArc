//! Turning past the last page (`comic-reader`, Reaching the end): the reader shows an
//! end screen instead of doing nothing. The screen marks the publication finished and
//! offers the next issue of its series, going back to the last page and the library.
//! Every key that goes back leaves it for the last screen; Home leaves it for the first.

use storyarc_core::domain::{Publication, SpreadLayout};
use storyarc_core::library::LibraryIndex;

use super::SpreadDecision;
use crate::keys::PageAction;

/// What a turn does to a reader that is on a page or on the end screen.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Turned {
    /// Nothing moves: the first screen going back, or the end screen going on.
    Stays,
    /// The reader lands on this page, leaving the end screen if it was on it.
    Page(usize),
    /// The reader turned past the last screen.
    End,
}

/// The outcome of `action` from `page`, or from the end screen when `at_end`.
pub fn turned(layout: &SpreadLayout, page: usize, at_end: bool, action: PageAction) -> Turned {
    let count = layout.count();
    if count == 0 {
        return Turned::Stays;
    }
    let last = layout.slot(count - 1).map_or(0, |spread| spread.leading);
    if at_end {
        return match action {
            PageAction::Next => Turned::Stays,
            PageAction::Previous | PageAction::Last => Turned::Page(last),
            PageAction::First => Turned::Page(layout.slot(0).map_or(0, |spread| spread.leading)),
        };
    }
    match SpreadDecision::turned(layout, page, action) {
        Some(landing) => Turned::Page(landing),
        None if action == PageAction::Next && layout.slot_containing(page) + 1 == count => {
            Turned::End
        }
        None => Turned::Stays,
    }
}

/// The next issue the end screen offers: the series' next openable publication the
/// library holds, by issue number (the core's rule, which Up next uses too).
pub fn next_in_series<'a>(
    publication: &Publication,
    library: &'a [Publication],
) -> Option<&'a Publication> {
    LibraryIndex::next(publication, library)
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use storyarc_core::domain::{MetadataOrigin, PublicationFormat, PublicationIdentity};

    use super::*;

    fn issue(series: &str, number: &str) -> Publication {
        let mut publication = Publication::new(
            PublicationIdentity::path(format!("/comics/{series} {number}.cbz")),
            PublicationFormat::Cbz,
            format!("{series} {number}"),
            MetadataOrigin::Inferred,
        );
        publication.series = Some(series.into());
        publication.number = Some(number.into());
        publication
    }

    #[test]
    fn turning_past_the_last_page_reaches_the_end_screen() {
        let single = SpreadLayout::single(3);
        assert_eq!(turned(&single, 1, false, PageAction::Next), Turned::Page(2));
        assert_eq!(turned(&single, 2, false, PageAction::Next), Turned::End);
        assert_eq!(turned(&single, 2, false, PageAction::Last), Turned::Stays);
        assert_eq!(
            turned(&single, 0, false, PageAction::Previous),
            Turned::Stays
        );
    }

    #[test]
    fn a_pair_on_the_last_screen_reaches_the_end_from_its_leading_page() {
        let paired = SpreadLayout::paired(5, &HashSet::new(), true);
        let last = paired
            .slot(paired.count() - 1)
            .expect("a last slot")
            .leading;
        assert_eq!(turned(&paired, last, false, PageAction::Next), Turned::End);
    }

    #[test]
    fn the_end_screen_goes_back_to_the_last_screen_and_no_further() {
        let single = SpreadLayout::single(4);
        assert_eq!(turned(&single, 3, true, PageAction::Next), Turned::Stays);
        assert_eq!(
            turned(&single, 3, true, PageAction::Previous),
            Turned::Page(3)
        );
        assert_eq!(turned(&single, 3, true, PageAction::Last), Turned::Page(3));
        assert_eq!(turned(&single, 3, true, PageAction::First), Turned::Page(0));
        assert_eq!(
            turned(&SpreadLayout::single(0), 0, false, PageAction::Next),
            Turned::Stays
        );
    }

    #[test]
    fn the_end_screen_offers_the_next_issue_of_the_series_or_nothing() {
        let library = [issue("Saga", "1"), issue("Saga", "3"), issue("Saga", "2")];
        let next = next_in_series(&library[0], &library).expect("issue 2 follows");
        assert_eq!(next.display_title, "Saga 2");
        assert!(next_in_series(&library[1], &library).is_none());
        let alone = Publication::new(
            PublicationIdentity::path("/comics/one-shot.cbz"),
            PublicationFormat::Cbz,
            "One Shot",
            MetadataOrigin::Inferred,
        );
        assert!(next_in_series(&alone, &library).is_none());
    }
}
