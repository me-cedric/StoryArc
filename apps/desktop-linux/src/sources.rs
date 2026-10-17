//! The folder libraries (task 2.31): chosen through `GtkFileDialog` and the portal,
//! kept in the sources file, scanned by the core on a worker, watched by the core's
//! `FolderWatcher` (polled for a portal grant, which passes no change events), and looked
//! at again every few seconds so a withdrawn grant turns grey and an unmounted volume
//! shows offline, then returns by itself. The rules are `folders.rs`.

use std::cell::{Cell, RefCell};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::domain::Publication;
use storyarc_core::io::CancelToken;
use storyarc_core::library::FolderSource;
use storyarc_core::paths::StorageLocations;
use storyarc_core::sources::SkipReason;
use storyarc_core::sources::watch::{Coverage, FolderWatcher, WatchOptions, WatchedFolder};

use crate::app::Shared;
use crate::folders::{self, Access, FolderRecord};
use crate::strings::{tr, tr_args};
use crate::{portal, session};

/// How often the window looks for changes the watcher reported, and at each folder's
/// access. Access is looked at every `ACCESS_EVERY` looks: ten seconds.
const LOOK: Duration = Duration::from_secs(1);
const ACCESS_EVERY: u32 = 10;

/// One chosen folder and what the last scan of it found.
pub struct SourceEntry {
    pub record: FolderRecord,
    pub access: Access,
    /// The grey line a polled folder carries, once.
    pub not_live: Option<String>,
    folder: Option<Arc<Mutex<FolderSource>>>,
    pub publications: Vec<Publication>,
    /// Files the scan recognised and could not open, each with its reason.
    pub skipped: Vec<(String, String)>,
    /// The downloads folder: its publications are in the library, and it is not one of
    /// the reader's folders, so no list shows it, no file saves it and none removes it.
    pub internal: bool,
}

impl SourceEntry {
    fn new(record: FolderRecord) -> Self {
        Self {
            internal: false,
            access: access_now(&record),
            record,
            not_live: None,
            folder: None,
            publications: Vec::new(),
            skipped: Vec::new(),
        }
    }
}

#[derive(Default)]
pub struct Sources {
    entries: RefCell<Vec<SourceEntry>>,
    watcher: RefCell<Option<FolderWatcher>>,
    changes: RefCell<Option<mpsc::Receiver<PathBuf>>>,
    looks: Cell<u32>,
}

impl Sources {
    /// Every publication of every folder, in the order the folders were chosen. A folder
    /// that is offline or needs access keeps what it held, so its place stays.
    pub fn publications(&self) -> Vec<Publication> {
        self.entries
            .borrow()
            .iter()
            .flat_map(|entry| entry.publications.iter().cloned())
            .collect()
    }

    /// The files no folder could open, by name, with the reason.
    pub fn skipped(&self) -> Vec<(String, String)> {
        self.entries
            .borrow()
            .iter()
            .flat_map(|entry| entry.skipped.iter().cloned())
            .collect()
    }

    /// The folders, for the sidebar: name, access, and the not-live line.
    pub fn summary(&self) -> Vec<(String, Access, Option<String>)> {
        self.entries
            .borrow()
            .iter()
            .filter(|entry| !entry.internal)
            .map(|entry| (entry.record.name(), entry.access, entry.not_live.clone()))
            .collect()
    }

    /// The name of the folder a publication came from, and whether it reads now.
    pub fn source_of(&self, publication: &Publication) -> Option<(String, Access)> {
        let path = publication.identity.normalized_path.as_deref()?;
        self.entries
            .borrow()
            .iter()
            .find(|entry| Path::new(path).starts_with(&entry.record.path))
            .map(|entry| (entry.record.name(), entry.access))
    }

    fn records(&self) -> Vec<FolderRecord> {
        self.entries
            .borrow()
            .iter()
            .filter(|entry| !entry.internal)
            .map(|entry| entry.record.clone())
            .collect()
    }
}

fn access_now(record: &FolderRecord) -> Access {
    let lists = std::fs::read_dir(&record.path).is_ok();
    Access::of(record, record.path.exists(), lists)
}

/// The words for a file a scan skipped.
fn skip_reason(reason: &SkipReason) -> String {
    let key = |key: &str, english: &str| tr(&format!("library.skipped.reason.{key}"), english);
    match reason {
        SkipReason::UnsupportedFormat(format) => tr_args(
            "library.skipped.reason.unsupported %s",
            "%s is not a format StoryArc reads",
            &[format],
        ),
        SkipReason::NotThere => key("notThere", "the file is not there"),
        SkipReason::FormatNotRecognised => {
            key("formatNotRecognised", "the format was not recognised")
        }
        SkipReason::ArchivePasswordProtected => key(
            "archivePasswordProtected",
            "the archive is password protected",
        ),
        SkipReason::ArchiveUnreadable => key("archiveUnreadable", "the archive could not be read"),
        SkipReason::ContentProtected => key(
            "contentProtected",
            "this audiobook is protected by its store’s content protection",
        ),
        SkipReason::Unknown => key("unknown", "it could not be read"),
    }
}

/// Reads the sources file, scans every folder that reads, starts the watcher and the
/// look that follows access.
pub fn start(shared: &Shared) {
    let records = folders::restore(&session::load_sources());
    let mut entries: Vec<SourceEntry> = records.into_iter().map(SourceEntry::new).collect();
    // The downloads folder comes last, so the reader's folders keep their places.
    let downloads = StorageLocations::current().downloads;
    let _ = std::fs::create_dir_all(&downloads);
    entries.push(SourceEntry {
        internal: true,
        ..SourceEntry::new(FolderRecord::new(downloads))
    });
    *shared.sources.entries.borrow_mut() = entries;
    for index in 0..shared.sources.entries.borrow().len() {
        scan(shared, index);
    }
    rewatch(shared);
    let weak = Rc::downgrade(shared);
    glib::timeout_add_local(LOOK, move || {
        let Some(shared) = weak.upgrade() else {
            return glib::ControlFlow::Break;
        };
        look(&shared);
        glib::ControlFlow::Continue
    });
}

/// One look: rescans the folders the watcher reported, and every ten seconds checks
/// each folder's access, rescanning a folder that came back.
fn look(shared: &Shared) {
    let changed: Vec<PathBuf> = shared
        .sources
        .changes
        .borrow()
        .as_ref()
        .map(|receiver| receiver.try_iter().collect())
        .unwrap_or_default();
    for root in changed {
        let index = shared
            .sources
            .entries
            .borrow()
            .iter()
            .position(|entry| entry.record.path == root);
        if let Some(index) = index {
            scan(shared, index);
        }
    }
    let looks = shared.sources.looks.get() + 1;
    shared.sources.looks.set(looks);
    if !looks.is_multiple_of(ACCESS_EVERY) {
        return;
    }
    let mut came_back = Vec::new();
    let mut moved = false;
    for (index, entry) in shared.sources.entries.borrow_mut().iter_mut().enumerate() {
        let now = access_now(&entry.record);
        if now != entry.access {
            moved = true;
            if now == Access::Readable {
                came_back.push(index);
            }
            entry.access = now;
        }
    }
    for index in came_back {
        scan(shared, index);
    }
    if moved {
        shared.library_changed();
    }
}

/// Rescans every folder that reads: the window gained focus, or the reader asked.
pub fn refresh(shared: &Shared) {
    for index in 0..shared.sources.entries.borrow().len() {
        scan(shared, index);
    }
}

/// Scans one folder on a worker: the first scan opens each publication once, later
/// scans reuse every file whose size and date are unchanged.
fn scan(shared: &Shared, index: usize) {
    let (path, folder) = {
        let entries = shared.sources.entries.borrow();
        let Some(entry) = entries.get(index) else {
            return;
        };
        if entry.access != Access::Readable {
            return;
        }
        (entry.record.path.clone(), entry.folder.clone())
    };
    let weak = Rc::downgrade(shared);
    glib::spawn_future_local(async move {
        let scanned = gio::spawn_blocking(move || {
            let cancel = CancelToken::new();
            let folder = match folder {
                Some(folder) => {
                    if let Ok(mut source) = folder.lock() {
                        source.rescan(&cancel);
                    }
                    folder
                }
                None => Arc::new(Mutex::new(FolderSource::open(&path, &cancel).ok()?)),
            };
            let (publications, skipped) = {
                let source = folder.lock().ok()?;
                let skipped = source
                    .skipped()
                    .iter()
                    .map(|file| (file_name(&file.path), skip_reason(&file.reason)))
                    .collect::<Vec<_>>();
                (source.publications().to_vec(), skipped)
            };
            Some((path, folder, publications, skipped))
        })
        .await;
        let (Some(shared), Ok(Some((path, folder, publications, skipped)))) =
            (weak.upgrade(), scanned)
        else {
            return;
        };
        let mut changed = false;
        if let Some(entry) = shared
            .sources
            .entries
            .borrow_mut()
            .iter_mut()
            .find(|entry| entry.record.path == path)
        {
            changed = entry.publications != publications || entry.skipped != skipped;
            entry.folder = Some(folder);
            entry.publications = publications;
            entry.skipped = skipped;
        }
        // A rescan that found nothing new leaves the grid, its scroll and its selection.
        if changed {
            shared.library_changed();
        }
    });
}

fn file_name(path: &str) -> String {
    Path::new(path).file_name().map_or_else(
        || path.to_owned(),
        |name| name.to_string_lossy().into_owned(),
    )
}

/// Watches every folder through the core: live where the system allows, polled for a
/// portal grant and past the system's limit, each polled folder named once in grey.
fn rewatch(shared: &Shared) {
    let folders: Vec<WatchedFolder> = shared
        .sources
        .records()
        .into_iter()
        .map(|record| WatchedFolder {
            path: record.path,
            is_portal_granted: record.portal_granted,
        })
        .collect();
    shared.sources.watcher.borrow_mut().take();
    let (sender, receiver) = mpsc::channel();
    let sender = Mutex::new(sender);
    let watcher = FolderWatcher::watch(folders, WatchOptions::default(), move |root| {
        if let Ok(sender) = sender.lock() {
            let _ = sender.send(root.to_path_buf());
        }
    });
    for coverage in watcher.coverage() {
        let note = match &coverage.coverage {
            Coverage::Live => None,
            Coverage::Polled { interval, .. } => {
                Some(folders::not_live_note(interval.as_secs().max(1)))
            }
        };
        if let Some(entry) = shared
            .sources
            .entries
            .borrow_mut()
            .iter_mut()
            .find(|entry| entry.record.path == coverage.path)
        {
            entry.not_live = note;
        }
    }
    *shared.sources.watcher.borrow_mut() = Some(watcher);
    *shared.sources.changes.borrow_mut() = Some(receiver);
}

/// Adds a folder the reader chose, saves the list, scans it and watches it.
pub fn add(shared: &Shared, path: PathBuf) {
    let mut records = shared.sources.records();
    if !folders::add(&mut records, path.clone()) {
        return;
    }
    let record = records.pop().expect("the folder was just added");
    // Before the downloads folder, which stays last.
    let index = shared.sources.entries.borrow().len().saturating_sub(1);
    shared
        .sources
        .entries
        .borrow_mut()
        .insert(index, SourceEntry::new(record));
    save(shared);
    scan(shared, index);
    rewatch(shared);
    shared.library_changed();
}

/// Choose Again on a folder that needs access: the new grant replaces the old one in
/// the same place, and the folder is scanned again.
fn replace(shared: &Shared, index: usize, path: PathBuf) {
    if let Some(entry) = shared.sources.entries.borrow_mut().get_mut(index) {
        *entry = SourceEntry::new(FolderRecord::new(path));
    }
    save(shared);
    scan(shared, index);
    rewatch(shared);
    shared.library_changed();
}

fn save(shared: &Shared) {
    session::save_sources(&folders::save(&shared.sources.records()));
}

/// Removes the folder library at `path`: its publications leave the library, the files
/// and the reading positions stay where they are.
pub fn remove(shared: &Shared, path: &Path) {
    let mut records = shared.sources.records();
    if !folders::remove(&mut records, path) {
        return;
    }
    shared
        .sources
        .entries
        .borrow_mut()
        .retain(|entry| entry.record.path != path);
    save(shared);
    rewatch(shared);
    shared.library_changed();
}

impl Sources {
    /// Each folder's path, in the sidebar's order, for the settings page.
    pub fn paths(&self) -> Vec<PathBuf> {
        self.entries
            .borrow()
            .iter()
            .filter(|entry| !entry.internal)
            .map(|entry| entry.record.path.clone())
            .collect()
    }

    /// How many publications a folder holds now.
    pub fn count_at(&self, path: &Path) -> usize {
        self.entries
            .borrow()
            .iter()
            .find(|entry| entry.record.path == path)
            .map_or(0, |entry| entry.publications.len())
    }
}

/// Add Folder: the system's folder chooser, through the portal.
pub fn choose(shared: &Shared, parent: &gtk::Window, again: Option<usize>) {
    let dialog = gtk::FileDialog::builder()
        .title("Add Folder")
        .modal(true)
        .build();
    let on = shared.clone();
    dialog.select_folder(
        Some(parent),
        None::<&gio::Cancellable>,
        move |result| match result {
            Ok(folder) => {
                let Some(path) = folder.path() else {
                    return;
                };
                match again {
                    Some(index) => replace(&on, index, path),
                    None => add(&on, path),
                }
            }
            Err(error) => portal::chooser_failed(&on, &error),
        },
    );
}

/// A folder dropped or opened is offered as a folder library, and added only when the
/// reader agrees (`desktop-experience`, Dropping a folder).
pub fn offer(shared: &Shared, folder: &Path) {
    // A folder that is already a library has nothing to offer: the library shows it.
    if shared
        .sources
        .records()
        .iter()
        .any(|record| record.path == folder)
    {
        return;
    }
    let name = FolderRecord::new(folder.to_path_buf()).name();
    let dialog = adw::AlertDialog::new(
        Some("Add Folder?"),
        Some(&format!(
            "Add “{name}” as a folder library. Its comics appear in the library."
        )),
    );
    dialog.add_responses(&[("cancel", "Cancel"), ("add", "Add Folder")]);
    dialog.set_response_appearance("add", adw::ResponseAppearance::Suggested);
    dialog.set_default_response(Some("add"));
    dialog.set_close_response("cancel");
    let on = shared.clone();
    let path = folder.to_path_buf();
    dialog.connect_response(None, move |_, response| {
        if response == "add" {
            add(&on, path.clone());
        }
    });
    let parent = shared.library.borrow().clone();
    dialog.present(parent.as_ref());
}

/// The sidebar's Choose Again: the one action a folder that needs access offers.
pub fn choose_again(shared: &Shared, parent: &gtk::Window, index: usize) {
    choose(shared, parent, Some(index));
}
