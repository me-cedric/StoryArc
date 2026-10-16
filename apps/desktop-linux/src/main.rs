//! StoryArc for Linux. The shell: windows, commands, preferences, theme and session.

mod app;
#[allow(dead_code)] // pure model; the parts no GTK code calls yet belong to 2.28 to 2.36
mod commands;
mod fullscreen;
mod idle;
#[allow(dead_code)] // pure model; the parts no GTK code calls yet belong to 2.28 to 2.36
mod keys;
mod library_window;
mod menus;
mod portal;
mod preferences_dialog;
#[allow(dead_code)] // pure model; the parts no GTK code calls yet belong to 2.28 to 2.36
mod progress;
mod publication;
mod reader_window;
mod session;
#[allow(dead_code)] // pure model; the parts no GTK code calls yet belong to 2.28 to 2.36
mod settings;
#[allow(dead_code)] // pure model; the parts no GTK code calls yet belong to 2.28 to 2.36
mod strings;
mod style;
mod theme;
mod window_state;
#[allow(dead_code)] // pure model; recording and forgetting a reader is the session file's own tests
mod windows;

// The grid, list and query rules are pure and tested; their widgets (tasks 2.35a to
// 2.35d) wait for the core's library API, so nothing calls them yet.
#[allow(dead_code)]
mod library;

use adw::prelude::*;
use gtk::{gdk, gio, glib};

use app::{App, Shared};
use publication::Publication;
use theme::Theme;
use windows::Open;

pub(crate) const APP_ID: &str = "com.mecedric.StoryArc";

fn main() -> glib::ExitCode {
    let application = adw::Application::builder().application_id(APP_ID).build();
    let shared = App::new();
    let _ = shared.application.set(application.clone());

    let on = shared.clone();
    application.connect_startup(move |application| startup(application, &on));
    let on = shared.clone();
    application.connect_activate(move |_| activate(&on));
    application.run()
}

fn startup(application: &adw::Application, shared: &Shared) {
    strings::init(
        &glib::language_names()
            .iter()
            .map(|name| name.to_string())
            .collect::<Vec<_>>(),
    );
    find_icon_when_uninstalled();
    install_theme(shared);
    install_actions(application, shared);
    menus::install_accelerators(application);
}

// ponytail: a debug build run from the tree has no installed icon, so it reads the source copy.
// An installed or Flatpak build finds the icon in hicolor and skips this.
fn find_icon_when_uninstalled() {
    if let (true, Some(display)) = (cfg!(debug_assertions), gdk::Display::default()) {
        gtk::IconTheme::for_display(&display)
            .add_search_path(concat!(env!("CARGO_MANIFEST_DIR"), "/data/icons"));
    }
}

/// The tokens, the ramp and the accent, then everything that can change them later:
/// the style manager's dark and high-contrast answers and the portal's accent.
fn install_theme(shared: &Shared) {
    let Some(display) = gdk::Display::default() else {
        return;
    };
    let _ = shared.theme.set(Theme::install(&display));
    shared.apply_theme();
    let manager = adw::StyleManager::default();
    for signal in ["notify::dark", "notify::high-contrast"] {
        let on = shared.clone();
        manager.connect_notify_local(Some(&signal["notify::".len()..]), move |_, _| {
            on.apply_theme();
        });
    }
    let on = shared.clone();
    portal::watch_accent(move |accent| on.system_accent_changed(accent));
}

fn install_actions(application: &adw::Application, shared: &Shared) {
    let on = shared.clone();
    let quit = gio::ActionEntry::builder("quit")
        .activate(move |app: &adw::Application, _, _| close_all_and_quit(app, &on))
        .build();
    let on = shared.clone();
    let preferences = gio::ActionEntry::builder("preferences")
        .activate(move |app: &adw::Application, _, _| {
            preferences_dialog::present(&on, app.active_window().as_ref());
        })
        .build();
    let shortcuts = gio::ActionEntry::builder("shortcuts")
        .activate(|app: &adw::Application, _, _| {
            menus::shortcuts_dialog().present(app.active_window().as_ref());
        })
        .build();
    let about = gio::ActionEntry::builder("about")
        .activate(|app: &adw::Application, _, _| show_about(app))
        .build();
    // The walk path until file opening lands (task 2.30): `gapplication action
    // com.mecedric.StoryArc open-reader "'/path/to/book.cbz'"`.
    let on = shared.clone();
    let open_reader = gio::ActionEntry::builder("open-reader")
        .parameter_type(Some(glib::VariantTy::STRING))
        .activate(move |_: &adw::Application, _, parameter| {
            if let Some(path) = parameter.and_then(|value| value.get::<String>()) {
                open_publication(&on, &path);
            }
        })
        .build();
    application.add_action_entries([quit, preferences, shortcuts, about, open_reader]);
    // Commands the table has and no wave 2 task implements yet stay in the menus, grey.
    for command in commands::COMMANDS {
        if let Some(name) = command.action.strip_prefix("app.")
            && application.lookup_action(name).is_none()
        {
            let action = gio::SimpleAction::new(name, None);
            action.set_enabled(false);
            application.add_action(&action);
        }
    }
}

/// Writes the session, then every reader's position, then closes every window and ends
/// the process even if one declined to close. A write that fails never stops any of it.
fn close_all_and_quit(application: &adw::Application, shared: &Shared) {
    shared.quitting.set(true);
    shared.save_session();
    let readers: Vec<_> = shared
        .readers
        .borrow()
        .iter()
        .map(|h| h.reader.clone())
        .collect();
    for reader in readers {
        reader.flush();
    }
    for window in application.windows() {
        window.close();
    }
    application.quit();
}

fn show_about(application: &adw::Application) {
    let dialog = adw::AboutDialog::builder()
        .application_name("StoryArc")
        .application_icon(APP_ID)
        .developer_name("Cédric Meyer")
        .version(storyarc_core::version())
        .license_type(gtk::License::MitX11)
        .build();
    dialog.present(application.active_window().as_ref());
}

/// Launch, or a second launch: present the library, restoring every window the last
/// run left open when there is none yet.
fn activate(shared: &Shared) {
    let library = shared.library.borrow().clone();
    if let Some(window) = library.filter(|window| window.is_visible()) {
        window.present();
        return;
    }
    let Some(display) = gdk::Display::default() else {
        return;
    };
    let plan = session::restore(&display, Publication::is_reachable);
    let mut missing = plan.missing;
    let mut readers = Vec::new();
    for reader in plan.readers {
        match Publication::open(std::path::Path::new(&reader.publication)) {
            Ok(publication) => readers.push((publication, reader)),
            Err(_) => missing.push(reader.publication),
        }
    }
    *shared.missing.borrow_mut() = missing.clone();
    let names: Vec<String> = missing.iter().map(|path| file_name(path)).collect();
    library_window::open(shared, &plan.library, &names);
    for (publication, reader) in readers {
        reader_window::open(shared, publication, reader.page, Some(reader.window));
    }
}

/// Opens a publication in a reader window, or brings forward the one that reads it.
fn open_publication(shared: &Shared, path: &str) {
    match shared.open(path) {
        Open::Present(_) => {
            if let Some(window) = shared.reader_for(path) {
                window.present();
            }
        }
        Open::New => match Publication::open(std::path::Path::new(path)) {
            Ok(publication) => {
                let page = session::FileProgressStore::page(&publication.id).unwrap_or(0);
                reader_window::open(shared, publication, page, None);
                shared.save_session();
            }
            Err(reason) => shared.toast(&reason),
        },
    }
}

fn file_name(path: &str) -> String {
    std::path::Path::new(path).file_name().map_or_else(
        || path.to_owned(),
        |name| name.to_string_lossy().into_owned(),
    )
}
