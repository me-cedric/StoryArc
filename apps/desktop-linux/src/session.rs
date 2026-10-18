//! The GTK side of what persists between two runs: which displays are connected, what
//! size each window has, the file the session lives in, the preferences file and the
//! core's progress store. The decisions are in `windows.rs`, `window_state.rs` and
//! `settings.rs`, which have no GTK in them.
//!
//! Everything lives under `$XDG_DATA_HOME/com.mecedric.StoryArc`, or the Flatpak
//! equivalent under `~/.var/app` (design, Decision 8). A write that fails is logged
//! and never holds a window or the app.

use std::path::PathBuf;
use std::rc::Rc;

use adw::prelude::*;
use gtk::{gdk, glib};
use storyarc_core::domain::{PublicationIdentity, ReadingPosition, ReadingProgress, Timestamp};
use storyarc_core::library;
use storyarc_core::paths::StorageLocations;
use storyarc_core::portability::{self, LibrarySnapshot};

use crate::library::search::SearchMemory;
use crate::library::shelf::ViewChoice;
use crate::progress::ProgressStore;
use crate::reading::adjust::Adjustments;
use crate::reading::direction::DirectionChoices;
use crate::reading::modes::ModeChoices;
use crate::settings::Preferences;
use crate::window_state::{Display, WindowState};
use crate::windows::{RestorePlan, SessionState};

/// The session file keeps wave 1's name: a wave 1 file still reads as the library window.
const SESSION_FILE: &str = "window-state";
const PREFERENCES_FILE: &str = "preferences";
const SOURCES_FILE: &str = "sources";
const REMOTE_FILE: &str = "remote-sources";
const LIBRARY_FILE: &str = "library-document.json";
/// What this device calls itself in a library document.
pub const DEVICE: &str = "linux";
const SYNC_FILE: &str = "sync-folder";
const QUEUE_FILE: &str = "downloads-queue.json";
const DIRECTIONS_FILE: &str = "reading-directions";
const SEARCH_FILE: &str = "search";
const VIEW_FILE: &str = "library-view";
const LOOKED_FILE: &str = "last-looked";
const SEEN_FILE: &str = "seen-version";
const MODES_FILE: &str = "page-turns";
const ADJUSTMENTS_FILE: &str = "image-adjustments";
const EPUB_LOOK_FILE: &str = "epub-look";
const EPUB_MARKS_FILE: &str = "epub-marks.json";
pub const LOG_DOMAIN: &str = "storyarc";

fn data_path(file: &str) -> PathBuf {
    glib::user_data_dir().join(crate::APP_ID).join(file)
}

fn write_file(path: &PathBuf, text: &str) {
    let written = path
        .parent()
        .map_or(Ok(()), std::fs::create_dir_all)
        .and_then(|()| std::fs::write(path, text));
    if let Err(error) = written {
        glib::g_warning!(LOG_DOMAIN, "Could not write {}: {error}", path.display());
    }
}

/// The saved session, fitted to the displays connected now, with the readers that can
/// be reopened and the names of those that cannot. A missing or damaged file gives the
/// default library window, so the app always opens.
pub fn restore(display: &gdk::Display, can_open: impl Fn(&str) -> bool) -> RestorePlan {
    let text = std::fs::read_to_string(data_path(SESSION_FILE)).unwrap_or_default();
    SessionState::restore(&text).plan(&connected(display), can_open)
}

/// Writes the session as it is now.
pub fn save(session: &SessionState) {
    write_file(&data_path(SESSION_FILE), &session.save());
}

/// Every monitor the display knows, as the pure module sees it.
fn connected(display: &gdk::Display) -> Vec<Display> {
    let monitors = display.monitors();
    (0..monitors.n_items())
        .filter_map(|index| monitors.item(index).and_downcast::<gdk::Monitor>())
        .map(|monitor| {
            let geometry = monitor.geometry();
            Display {
                connector: monitor.connector().map(Into::into).unwrap_or_default(),
                width: geometry.width(),
                height: geometry.height(),
            }
        })
        .collect()
}

/// A window's state as it is now: its size, whether it is maximized and the
/// display it is on. A full-screen window reports the size it will return to.
pub fn capture(window: &adw::ApplicationWindow) -> WindowState {
    let (width, height) = window.default_size();
    let display = window
        .surface()
        .and_then(|surface| gtk::prelude::WidgetExt::display(window).monitor_at_surface(&surface))
        .and_then(|monitor| monitor.connector())
        .map(Into::into);
    WindowState {
        width,
        height,
        maximized: window.is_maximized(),
        display,
    }
}

/// Sizes a window from its saved state. Wayland decides where it goes.
pub fn apply(window: &adw::ApplicationWindow, state: &WindowState) {
    window.set_default_size(state.width, state.height);
    if state.maximized {
        window.maximize();
    }
}

pub fn load_preferences() -> Preferences {
    let text = std::fs::read_to_string(data_path(PREFERENCES_FILE)).unwrap_or_default();
    Preferences::restore(&text)
}

pub fn save_preferences(preferences: &Preferences) {
    write_file(&data_path(PREFERENCES_FILE), &preferences.save());
}

/// The look of a reflowable book: the theme and the reader's typography (`epub_look.rs`).
pub fn load_epub_look() -> crate::epub_look::Look {
    crate::epub_look::Look::restore(&std::fs::read_to_string(data_path(EPUB_LOOK_FILE)).unwrap_or_default())
}

pub fn save_epub_look(look: &crate::epub_look::Look) {
    write_file(&data_path(EPUB_LOOK_FILE), &look.save());
}

/// The bookmarks and highlights of one EPUB, by its key (`epub_marks.rs`).
pub fn load_epub_marks(key: &str) -> crate::epub_marks::Marks {
    let all = crate::epub_marks::read_all(&std::fs::read_to_string(data_path(EPUB_MARKS_FILE)).unwrap_or_default());
    all.get(key).map(crate::epub_marks::Marks::from_json).unwrap_or_default()
}

pub fn save_epub_marks(key: &str, marks: &crate::epub_marks::Marks) {
    let path = data_path(EPUB_MARKS_FILE);
    let mut all = crate::epub_marks::read_all(&std::fs::read_to_string(&path).unwrap_or_default());
    all.insert(key.to_owned(), marks.to_json());
    write_file(&path, &serde_json::Value::Object(all).to_string());
}

/// The recent searches and the search scope (`library/search.rs`).
pub fn load_search() -> SearchMemory {
    SearchMemory::restore(&std::fs::read_to_string(data_path(SEARCH_FILE)).unwrap_or_default())
}

pub fn save_search(memory: &SearchMemory) {
    write_file(&data_path(SEARCH_FILE), &memory.save());
}

/// Grid or list, series or issues (`library/shelf.rs`).
pub fn load_view() -> ViewChoice {
    ViewChoice::restore(&std::fs::read_to_string(data_path(VIEW_FILE)).unwrap_or_default())
}

pub fn save_view(view: ViewChoice) {
    write_file(&data_path(VIEW_FILE), &view.save());
}

/// When the reader last looked at the library before now, and records now as the next
/// run's answer. `None` on a first launch.
pub fn looked_now() -> Option<Timestamp> {
    let path = data_path(LOOKED_FILE);
    let previous = std::fs::read_to_string(&path)
        .ok()
        .and_then(|text| text.trim().parse::<i64>().ok())
        .map(Timestamp);
    write_file(&path, &format!("{}\n", Timestamp::now().0));
    previous
}

/// Forgets every reading position this device holds (`reading-progress`, Clearing
/// history).
pub fn forget_history(store: &library::ProgressStore) -> Result<(), String> {
    store
        .store()
        .clear_progress()
        .map_err(|error| error.to_string())
}

/// The version whose changes the reader was last told about (`about.rs`).
pub fn seen_version() -> Option<String> {
    std::fs::read_to_string(data_path(SEEN_FILE))
        .ok()
        .map(|text| text.trim().to_owned())
        .filter(|version| !version.is_empty())
}

pub fn save_seen_version(version: &str) {
    write_file(&data_path(SEEN_FILE), &format!("{version}\n"));
}

/// The page turns by series and the scroll places (`reading/modes.rs`).
pub fn load_modes() -> ModeChoices {
    ModeChoices::restore(&std::fs::read_to_string(data_path(MODES_FILE)).unwrap_or_default())
}

pub fn save_modes(modes: &ModeChoices) {
    write_file(&data_path(MODES_FILE), &modes.save());
}

/// The image adjustments by series (`reading/adjust.rs`).
pub fn load_adjustments() -> Adjustments {
    Adjustments::restore(&std::fs::read_to_string(data_path(ADJUSTMENTS_FILE)).unwrap_or_default())
}

pub fn save_adjustments(adjustments: &Adjustments) {
    write_file(&data_path(ADJUSTMENTS_FILE), &adjustments.save());
}

/// The reading directions the reader chose (`reading/direction.rs`).
pub fn load_directions() -> DirectionChoices {
    let text = std::fs::read_to_string(data_path(DIRECTIONS_FILE)).unwrap_or_default();
    DirectionChoices::restore(&text)
}

pub fn save_directions(text: &str) {
    write_file(&data_path(DIRECTIONS_FILE), text);
}

/// The chosen folders as the sources file keeps them (`folders.rs`).
pub fn load_sources() -> String {
    std::fs::read_to_string(data_path(SOURCES_FILE)).unwrap_or_default()
}

pub fn save_sources(text: &str) {
    write_file(&data_path(SOURCES_FILE), text);
}

/// The network libraries as their file keeps them (`remote_sources.rs`): no secret in it.
pub fn load_remote_sources() -> String {
    std::fs::read_to_string(data_path(REMOTE_FILE)).unwrap_or_default()
}

pub fn save_remote_sources(text: &str) {
    write_file(&data_path(REMOTE_FILE), text);
}

/// What this device keeps of the library document: the shelves, the pins and the
/// deletions, in the document's own format, so a sync merges what this file holds.
pub fn load_library_snapshot() -> LibrarySnapshot {
    let Ok(bytes) = std::fs::read(data_path(LIBRARY_FILE)) else {
        return LibrarySnapshot::default();
    };
    portability::decode(&bytes)
        .map(|document| {
            portability::merging(&document, &LibrarySnapshot::default(), DEVICE).snapshot
        })
        .unwrap_or_default()
}

pub fn save_library_snapshot(snapshot: &LibrarySnapshot) {
    let document = snapshot.document(storyarc_core::version(), Timestamp::now(), DEVICE, false);
    let bytes = portability::encode(&document);
    let path = data_path(LIBRARY_FILE);
    let written = path
        .parent()
        .map_or(Ok(()), std::fs::create_dir_all)
        .and_then(|()| std::fs::write(&path, bytes));
    if let Err(error) = written {
        glib::g_warning!(LOG_DOMAIN, "Could not write {}: {error}", path.display());
    }
}

/// The folder the sync document lives in, when the reader chose one.
pub fn load_sync_folder() -> Option<PathBuf> {
    let text = std::fs::read_to_string(data_path(SYNC_FILE)).ok()?;
    let line = text.lines().next()?.trim();
    (!line.is_empty()).then(|| PathBuf::from(line))
}

pub fn save_sync_folder(folder: Option<&std::path::Path>) {
    write_file(
        &data_path(SYNC_FILE),
        &folder.map_or_else(String::new, |f| format!("{}\n", f.display())),
    );
}

/// Where the download queue is kept between runs.
pub fn queue_path() -> PathBuf {
    data_path(QUEUE_FILE)
}

/// Opens the core's progress store (ADR-0006) where the core says it lives, or one in
/// memory when the disk refuses, so reading never waits on a store. A failure is logged.
pub fn open_progress_store() -> library::ProgressStore {
    let path = StorageLocations::current().store_file();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    library::ProgressStore::open(&path).unwrap_or_else(|error| {
        glib::g_warning!(LOG_DOMAIN, "Could not open {}: {error}", path.display());
        library::ProgressStore::in_memory().expect("an in-memory store always opens")
    })
}

/// One publication's place in the core's store. The last page counts as finished, and
/// finished stays finished (the store's own rule).
pub struct CoreProgress {
    store: Rc<library::ProgressStore>,
    identity: PublicationIdentity,
    page_count: u32,
}

impl CoreProgress {
    pub fn new(
        store: Rc<library::ProgressStore>,
        identity: PublicationIdentity,
        page_count: u32,
    ) -> Self {
        Self {
            store,
            identity,
            page_count,
        }
    }

    /// The page last written for a publication, counted from zero.
    pub fn page(store: &library::ProgressStore, identity: &PublicationIdentity) -> Option<u32> {
        match store.read(identity).ok()??.position {
            ReadingPosition::Page { index, .. } => u32::try_from(index).ok(),
            _ => None,
        }
    }
}

impl ProgressStore for CoreProgress {
    fn write(&mut self, _publication: &str, page: u32) -> Result<(), String> {
        let now = Timestamp::now();
        let position = ReadingPosition::page(i64::from(page), i64::from(self.page_count));
        let record = ReadingProgress::new(self.identity.clone(), position, now);
        let record = if page + 1 >= self.page_count {
            record.finished(true, now)
        } else {
            record
        };
        self.store.write(&record).map_err(|error| error.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_position_reads_back_and_the_last_page_is_finished() {
        let store = Rc::new(library::ProgressStore::in_memory().expect("store"));
        let identity = PublicationIdentity::path("/comics/a.cbz");
        let mut progress = CoreProgress::new(store.clone(), identity.clone(), 10);
        assert_eq!(CoreProgress::page(&store, &identity), None);
        progress.write("/comics/a.cbz", 4).expect("written");
        assert_eq!(CoreProgress::page(&store, &identity), Some(4));
        let record = store.read(&identity).expect("read").expect("a record");
        assert!(!record.is_finished);
        progress.write("/comics/a.cbz", 9).expect("written");
        let record = store.read(&identity).expect("read").expect("a record");
        assert!(record.is_finished);
    }

    #[test]
    fn clearing_the_history_forgets_every_position_and_nothing_else() {
        let store = Rc::new(library::ProgressStore::in_memory().expect("store"));
        let first = PublicationIdentity::path("/comics/a.cbz");
        let second = PublicationIdentity::path("/comics/b.cbz");
        for (identity, path, page) in [(&first, "/comics/a.cbz", 3), (&second, "/comics/b.cbz", 9)]
        {
            CoreProgress::new(store.clone(), identity.clone(), 10)
                .write(path, page)
                .expect("written");
        }
        assert_eq!(store.recent(usize::MAX).expect("recent").len(), 2);
        forget_history(&store).expect("cleared");
        assert_eq!(store.recent(usize::MAX).expect("recent").len(), 0);
        assert_eq!(CoreProgress::page(&store, &first), None);
        assert_eq!(CoreProgress::page(&store, &second), None);
    }
}
