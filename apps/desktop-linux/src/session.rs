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

use crate::progress::ProgressStore;
use crate::settings::Preferences;
use crate::window_state::{Display, WindowState};
use crate::windows::{RestorePlan, SessionState};

/// The session file keeps wave 1's name: a wave 1 file still reads as the library window.
const SESSION_FILE: &str = "window-state";
const PREFERENCES_FILE: &str = "preferences";
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
}
