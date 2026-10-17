//! The menu on a cover (a right click, or Shift and F10 / the Menu key on a focused
//! cell): what a reader can do to one publication without opening a page first. Start
//! from the beginning lives here and nowhere else (`reading-progress`, Restart
//! deliberately): only on one publication, only when it has a place to forget, and never
//! as a page's primary action.

use storyarc_core::library::{ProgressSummary, ReadState};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CellAction {
    /// Open the publication in a reader, where it was left.
    Read,
    /// Show the publication's page.
    ShowDetails,
    /// Forget the place, after a confirmation.
    StartOver,
    /// Open the folder that holds the file.
    ShowInFiles,
}

impl CellAction {
    /// The action's name in the cell's action group.
    pub fn name(self) -> &'static str {
        match self {
            Self::Read => "read",
            Self::ShowDetails => "show-details",
            Self::StartOver => "start-over",
            Self::ShowInFiles => "show-in-files",
        }
    }

    /// The catalogue key and the English text.
    pub fn label(self) -> (&'static str, &'static str) {
        match self {
            Self::Read => ("library.action.open", "Open"),
            Self::ShowDetails => ("library.action.showDetails", "Show details"),
            Self::StartOver => ("library.restart", "Start from the beginning"),
            Self::ShowInFiles => ("detail.showInFolder", "Show in folder"),
        }
    }
}

/// The actions a cover offers, in menu order. `readable` is whether its folder can be
/// read now; `selected` is how many covers the action would apply to.
pub fn cell_actions(summary: ProgressSummary, readable: bool, selected: usize) -> Vec<CellAction> {
    let mut actions = Vec::new();
    if readable {
        actions.push(CellAction::Read);
    }
    actions.push(CellAction::ShowDetails);
    if summary.state != ReadState::Unread && selected <= 1 {
        actions.push(CellAction::StartOver);
    }
    actions.push(CellAction::ShowInFiles);
    actions
}

#[cfg(test)]
mod tests {
    use storyarc_core::domain::{
        MetadataOrigin, Publication, PublicationFormat, PublicationIdentity, Timestamp,
    };

    use super::*;
    use crate::library::adapter::tests::reading;

    fn summary(index: i64, finished: bool) -> ProgressSummary {
        let publication = Publication::new(
            PublicationIdentity::path("/a.cbz"),
            PublicationFormat::Cbz,
            "A",
            MetadataOrigin::Inferred,
        );
        let record = reading(&publication, index, 10, 5);
        let record = if finished {
            record.finished(true, Timestamp(9))
        } else {
            record
        };
        ProgressSummary::of(Some(&record))
    }

    #[test]
    fn starting_over_is_offered_only_on_a_publication_with_a_place_to_forget() {
        assert!(!cell_actions(ProgressSummary::UNREAD, true, 1).contains(&CellAction::StartOver));
        assert!(cell_actions(summary(4, false), true, 1).contains(&CellAction::StartOver));
        assert!(cell_actions(summary(9, true), true, 1).contains(&CellAction::StartOver));
    }

    #[test]
    fn starting_over_is_never_offered_for_several_at_once() {
        assert!(!cell_actions(summary(4, false), true, 3).contains(&CellAction::StartOver));
    }

    #[test]
    fn a_publication_on_a_folder_that_cannot_be_read_offers_no_read() {
        assert_eq!(
            cell_actions(ProgressSummary::UNREAD, false, 1),
            [CellAction::ShowDetails, CellAction::ShowInFiles]
        );
        assert_eq!(
            cell_actions(summary(4, false), true, 1),
            [
                CellAction::Read,
                CellAction::ShowDetails,
                CellAction::StartOver,
                CellAction::ShowInFiles
            ]
        );
    }
}
