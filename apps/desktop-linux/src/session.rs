//! The GTK side of what persists between two runs: which displays are connected, what
//! size each window has, the file the session lives in, the preferences file and the
//! progress file. The decisions are in `windows.rs`, `window_state.rs` and
//! `settings.rs`, which have no GTK in them.
//!
//! Everything lives under `$XDG_DATA_HOME/com.mecedric.StoryArc`, or the Flatpak
//! equivalent under `~/.var/app` (design, Decision 8). A write that fails is logged
//! and never holds a window or the app.

use std::collections::BTreeMap;
use std::path::PathBuf;

use adw::prelude::*;
use gtk::{gdk, glib};

use crate::progress::ProgressStore;
use crate::settings::Preferences;
use crate::window_state::{Display, WindowState};
use crate::windows::{RestorePlan, SessionState};

/// The session file keeps wave 1's name: a wave 1 file still reads as the library window.
const SESSION_FILE: &str = "window-state";
const PREFERENCES_FILE: &str = "preferences";
const PROGRESS_FILE: &str = "progress";
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

/// The reading positions, one `publication=page` line each, until the core's progress
/// store (task 2.1) replaces it. Every write rewrites the file, which is small.
#[derive(Debug, Default)]
pub struct FileProgressStore;

impl FileProgressStore {
    fn read_all() -> BTreeMap<String, u32> {
        std::fs::read_to_string(data_path(PROGRESS_FILE))
            .unwrap_or_default()
            .lines()
            .filter_map(|line| line.rsplit_once('='))
            .filter_map(|(publication, page)| Some((publication.to_owned(), page.trim().parse().ok()?)))
            .collect()
    }

    /// The page last written for a publication, counted from zero.
    pub fn page(publication: &str) -> Option<u32> {
        Self::read_all().get(publication).copied()
    }
}

impl ProgressStore for FileProgressStore {
    fn write(&mut self, publication: &str, page: u32) -> Result<(), String> {
        let mut all = Self::read_all();
        all.insert(publication.to_owned(), page);
        let text: String = all
            .iter()
            .map(|(publication, page)| format!("{publication}={page}\n"))
            .collect();
        let path = data_path(PROGRESS_FILE);
        path.parent()
            .map_or(Ok(()), std::fs::create_dir_all)
            .and_then(|()| std::fs::write(&path, text))
            .map_err(|error| format!("{}: {error}", path.display()))
    }
}
