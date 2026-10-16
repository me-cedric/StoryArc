//! The GTK side of the window state: which displays are connected, what size
//! the window has, and the file the state lives in. The logic is in
//! `window_state.rs`, which has no GTK in it.

use std::path::PathBuf;

use adw::prelude::*;
use gtk::{gdk, glib};

use crate::window_state::{Display, WindowState};

const FILE_NAME: &str = "window-state";
const LOG_DOMAIN: &str = "storyarc";

/// `$XDG_DATA_HOME/com.mecedric.StoryArc/window-state`, or the Flatpak
/// equivalent under `~/.var/app` (design, Decision 8).
fn state_path() -> PathBuf {
    glib::user_data_dir().join(crate::APP_ID).join(FILE_NAME)
}

/// The saved state, fitted to the displays connected now. A missing or damaged
/// file gives the default state, so the window always opens.
pub fn restore(display: &gdk::Display) -> WindowState {
    let text = std::fs::read_to_string(state_path()).unwrap_or_default();
    WindowState::restore(&text).fit(&connected(display))
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

/// Writes the window's state. A write that fails is logged and the window still
/// closes: the spec says a failed write never holds a window or the app.
pub fn save(window: &adw::ApplicationWindow) {
    let (width, height) = window.default_size();
    let display = window
        .surface()
        .and_then(|surface| gtk::prelude::WidgetExt::display(window).monitor_at_surface(&surface))
        .and_then(|monitor| monitor.connector())
        .map(Into::into);
    let state = WindowState {
        width,
        height,
        maximized: window.is_maximized(),
        display,
    };
    let path = state_path();
    let written = path
        .parent()
        .map_or(Ok(()), std::fs::create_dir_all)
        .and_then(|()| std::fs::write(&path, state.save()));
    if let Err(error) = written {
        glib::g_warning!(
            LOG_DOMAIN,
            "Could not save the window state to {}: {error}",
            path.display()
        );
    }
}
