//! Sync when the app runs (task 3.19; `desktop-experience`, *Sync when the app runs*): the
//! sync document in the folder the reader chose is merged at start, on a worker, before the
//! window waits for anything; and written once more at quit when a position changed, within
//! five seconds, whatever the result. An unreachable folder is grey, never red. The rules
//! are `sync_rules.rs`; the merge and the file are the core's `LibrarySync`.

use std::path::PathBuf;

use gtk::{gio, glib};
use storyarc_core::domain::Timestamp;
use storyarc_core::portability::{
    FolderPlace, LibrarySnapshot, LibrarySync, SyncOutcome, document::DocumentSource,
};

use crate::app::Shared;
use crate::session::{self, LOG_DOMAIN};
use crate::strings::tr;
use crate::sync_rules::{self, SyncResult};

/// What this device writes into the sync document: its shelves and pins, its network
/// libraries (without secrets) and every reading position.
pub fn snapshot(shared: &Shared) -> LibrarySnapshot {
    let mut snapshot = shared.document.borrow().clone();
    snapshot.sources = shared
        .remote
        .entries
        .borrow()
        .iter()
        .map(|entry| DocumentSource {
            id: entry.record.id.clone(),
            display_name: entry.record.name.clone(),
            kind: entry.record.kind.document_kind().to_owned(),
            last_successful_sync: None,
            locator: Some(entry.record.address.clone()),
            needs_sign_in: entry.grey.is_some(),
        })
        .collect();
    snapshot.progress = shared
        .progress_store()
        .recent(usize::MAX)
        .unwrap_or_default();
    snapshot
}

fn run(folder: PathBuf, snapshot: LibrarySnapshot) -> Option<(bool, Option<LibrarySnapshot>)> {
    let sync = LibrarySync::new(
        FolderPlace::new(folder),
        session::DEVICE,
        storyarc_core::version(),
    );
    match sync.sync(&snapshot, Timestamp::now()) {
        Ok(SyncOutcome::Synced { merged, .. }) => Some((true, Some(merged.snapshot))),
        Ok(SyncOutcome::Refused(_) | SyncOutcome::Busy) => Some((true, None)),
        Err(_) => Some((false, None)),
    }
}

/// What a merge brought in: the shelves, pins and deletions are kept, and each position
/// is written through the progress store, which keeps the furthest.
fn apply(shared: &Shared, merged: LibrarySnapshot) {
    let store = shared.progress_store();
    for record in &merged.progress {
        if let Err(error) = store.write(record) {
            glib::g_warning!(LOG_DOMAIN, "Could not keep a synced position: {error}");
        }
    }
    {
        let mut document = shared.document.borrow_mut();
        document.shelves = merged.shelves;
        document.pinned_shelves = merged.pinned_shelves;
        document.removed_shelves = merged.removed_shelves;
        document.covers = merged.covers;
        session::save_library_snapshot(&document);
    }
    shared.library_changed();
}

/// The grey line the Sync row says, for what the last sync came to.
pub fn line(result: &SyncResult) -> String {
    match result {
        SyncResult::Synced => tr("sync.status.synced", "Synced"),
        SyncResult::Unreachable => tr(
            "sync.status.unreachable.place",
            "The sync folder cannot be reached. StoryArc syncs again when it can.",
        ),
        SyncResult::TimedOut => tr(
            "sync.status.timedOut",
            "The sync folder did not answer in time. StoryArc syncs again next time.",
        ),
    }
}

/// At start: merge on a worker. The window is already up and never waits for this.
pub fn at_start(shared: &Shared) {
    let Some(folder) = session::load_sync_folder() else {
        return;
    };
    let snapshot = snapshot(shared);
    let on = shared.clone();
    glib::spawn_future_local(async move {
        let result = gio::spawn_blocking(move || run(folder, snapshot)).await;
        match result {
            Ok(Some((true, Some(merged)))) => {
                *on.sync_line.borrow_mut() = line(&SyncResult::Synced);
                apply(&on, merged);
            }
            Ok(Some((false, _))) => {
                *on.sync_line.borrow_mut() = line(&SyncResult::Unreachable);
            }
            _ => {}
        }
    });
}

/// At quit: write the document once more when a position changed, for at most five
/// seconds. The result changes nothing about quitting.
pub fn at_quit(shared: &Shared) -> Option<SyncResult> {
    let folder = session::load_sync_folder();
    if !sync_rules::writes_at_quit(shared.position_changed.get(), folder.is_some()) {
        return None;
    }
    let snapshot = snapshot(shared);
    let folder = folder?;
    let answer = sync_rules::within(sync_rules::QUIT_BUDGET, move || {
        run(folder, snapshot).map(|(reached, _)| reached)
    });
    Some(sync_rules::quit_result(answer.flatten()))
}

/// Sync now, from the Settings row: the same merge as at start.
pub fn now(shared: &Shared) {
    at_start(shared);
}
