//! What the library window reads to fill its cells, Home's cards and the publication
//! page: the progress store, each folder's access, and the cells a publication or a
//! series becomes.

use std::path::PathBuf;
use std::rc::Rc;

use storyarc_core::domain::Publication;
use storyarc_core::library::{ProgressIndex, ProgressSummary};

use crate::app::Shared;
use crate::detail_panes;
use crate::detail_view::DetailHooks;
use crate::folders::Access;
use crate::home_view::CardState;
use crate::launch;
use crate::library::detail::{self, Detail};
use crate::library::entry::{LibraryEntry, Progress};
use crate::library_views::Item;
use crate::settings;

/// The progress records the library reads at most, newest first.
const PROGRESS_RECORDS: usize = 100_000;

pub(crate) fn progress_index(shared: &Shared) -> ProgressIndex {
    ProgressIndex::new(
        shared
            .progress_store()
            .recent(PROGRESS_RECORDS)
            .unwrap_or_default(),
    )
}

/// A publication's progress as the library reads it now.
pub(crate) fn summary_of(shared: &Shared, publication: &Publication) -> ProgressSummary {
    progress_index(shared).summary(publication)
}

/// Shows a publication's page: beside the library in a wide window, pushed over it in a
/// narrow one (`detail_panes.rs`).
pub(crate) fn show_detail(shared: &Shared, publication: &Publication) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    *ui.panes.chosen.borrow_mut() = Some(publication.clone());
    detail_panes::place(shared, &ui);
}

/// The detail of a publication as it stands now: its progress and its folder's access.
pub(crate) fn detail_of(shared: &Shared, publication: &Publication) -> Detail {
    Detail::of(
        publication,
        progress_index(shared).summary(publication),
        shared.sources.source_of(publication),
    )
}

/// What the page needs besides its detail: reading, other pages, the rest of the
/// series with their marks, and the accent a coverless page falls back to.
pub(crate) fn detail_hooks(shared: &Shared, publication: &Publication) -> DetailHooks {
    let progress = progress_index(shared);
    let others = detail::other_issues(publication, &shared.sources.publications())
        .into_iter()
        .map(|other| {
            let state = card_state(shared, &progress, &other);
            (other, state)
        })
        .collect();
    let weak = Rc::downgrade(shared);
    DetailHooks {
        read: read(shared),
        show: Rc::new(move |other: &Publication| {
            if let Some(shared) = weak.upgrade() {
                show_detail(&shared, other);
            }
        }),
        others,
        accent: settings::chrome_accent(shared.preferences().accent, shared.system_accent.get()),
        stopped: crate::player::stopped_at(shared, &publication.identity),
        listen_from: listen_from(shared),
    }
}

pub(crate) fn card_state(
    shared: &Shared,
    progress: &ProgressIndex,
    publication: &Publication,
) -> CardState {
    let percent = match Progress::of(progress.summary(publication)) {
        Progress::Unread => None,
        started => Some(started.percent()),
    };
    CardState {
        percent,
        unavailable: shared
            .sources
            .source_of(publication)
            .is_some_and(|(_, access)| access != Access::Readable),
    }
}

/// Starts an audiobook at a chapter, leaving where it was left until the listener moves
/// (`audio-playback`, *Starting from a chapter*).
fn listen_from(shared: &Shared) -> crate::detail_view::ListenFrom {
    let weak = Rc::downgrade(shared);
    Rc::new(move |publication: &Publication, part, start| {
        let Some(shared) = weak.upgrade() else {
            return;
        };
        let Some(path) = publication.identity.normalized_path.clone().map(PathBuf::from) else {
            return;
        };
        match shared.player().play_audiobook(publication, &path, Some((part, start))) {
            Ok(()) => crate::player_window::present(&shared),
            Err(reason) => shared.toast(&reason),
        }
    })
}

/// Opens a publication in a reader window, naming a refusal in grey.
pub(crate) fn read(shared: &Shared) -> Rc<dyn Fn(&Publication)> {
    let weak = Rc::downgrade(shared);
    Rc::new(move |publication: &Publication| {
        let Some(shared) = weak.upgrade() else {
            return;
        };
        let Some(path) = publication.identity.normalized_path.clone() else {
            return;
        };
        if let Err(reason) = launch::open_publication(&shared, &PathBuf::from(path)) {
            shared.toast(&reason);
        }
    })
}
/// The cell for one publication, dimmed when its folder cannot be read now.
pub(crate) fn item_for(shared: &Shared, publication: &Publication) -> Item {
    let source = shared.sources.source_of(publication);
    let (name, access) = source.unwrap_or_else(|| (String::new(), Access::Readable));
    let entry = LibraryEntry::from_core(publication, summary_of(shared, publication), &name)
        .with_access(access);
    Item::publication(entry, publication.clone())
}

/// The cell for a series: its name, its first issue's cover and folder, and how far
/// through the series the reader is, by issues finished.
pub(crate) fn series_item(
    shared: &Shared,
    progress: &ProgressIndex,
    name: String,
    issues: Vec<Publication>,
) -> Item {
    let first = &issues[0];
    let source = shared.sources.source_of(first);
    let (folder, access) = source.unwrap_or_else(|| (String::new(), Access::Readable));
    let finished = issues
        .iter()
        .filter(|issue| {
            progress
                .record(issue)
                .is_some_and(|record| record.is_finished)
        })
        .count();
    let mut entry =
        LibraryEntry::from_core(first, ProgressSummary::UNREAD, &folder).with_access(access);
    entry.id = format!("series:{name}");
    entry.title = name;
    entry.series = None;
    entry.progress = match finished {
        0 => Progress::Unread,
        done if done == issues.len() => Progress::Finished,
        done => Progress::Reading {
            index: u32::try_from(done).unwrap_or(0),
            of: u32::try_from(issues.len()).unwrap_or(1),
        },
    };
    Item {
        entry,
        publication: None,
        issues,
    }
}
