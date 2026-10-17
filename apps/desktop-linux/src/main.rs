//! StoryArc for Linux. The shell: windows, commands, preferences, theme and session, the
//! library over the core's folder sources, and readers over the core's decoder.

mod about;
mod app;
mod audio;
#[allow(dead_code)] // pure model; the parts no GTK code calls yet belong to later tasks
mod commands;
mod cover_colour;
mod covers;
mod detail_panes;
mod detail_view;
mod diagnostic_export;
mod download_rules;
mod downloads_ui;
mod epub_host;
mod epub_view;
mod epub_window;
mod folders;
mod fullscreen;
mod home_view;
mod idle;
#[allow(dead_code)] // pure model; the parts no GTK code calls yet belong to later tasks
mod keys;
mod launch;
mod library_cells;
mod library_data;
mod library_find;
mod library_menus;
mod library_notices;
mod library_search;
mod library_selection;
mod library_views;
mod library_window;
mod link;
mod menus;
mod mpris;
mod network_ui;
mod opening;
mod page_view;
mod pdf_ui;
mod player;
mod player_ui;
mod portal;
mod preferences_dialog;
mod preferences_pages;
#[allow(dead_code)] // pure model; the parts no GTK code calls yet belong to later tasks
mod progress;
mod publication;
mod reader_adjust;
mod reader_browser;
mod reader_end;
mod reader_input;
mod reader_modes;
mod reader_scroll;
mod reader_window;
mod reading;
mod remote_browse;
mod remote_sources;
#[cfg(test)]
mod scratch;
mod secret_state;
mod services;
mod session;
#[allow(dead_code)] // pure model; the parts no GTK code calls yet belong to later tasks
mod settings;
mod shelf_rules;
mod shelf_ui;
mod sources;
mod speech;
mod storage_rules;
mod storage_ui;
#[allow(dead_code)] // pure model; the parts no GTK code calls yet belong to later tasks
mod strings;
mod style;
mod sync_rules;
mod sync_ui;
mod theme;
mod window_state;
#[allow(dead_code)] // pure model; recording and forgetting a reader is the session file's own tests
mod windows;

// The grid's tier rules, the selection model and the local query over cells are pure
// and tested; GTK's own grid selection and the core's queries are what the window uses.
#[allow(dead_code)]
mod library;

use std::path::PathBuf;

use adw::prelude::*;
use gtk::{gdk, gio, glib};

use app::{App, Shared};
use publication::Publication;
use theme::Theme;

pub(crate) const APP_ID: &str = "com.mecedric.StoryArc";

fn main() -> glib::ExitCode {
    // HANDLES_OPEN: the desktop entry declares the comic types and `Exec=storyarc %F`,
    // and a second launch hands its files to the running instance (task 2.30).
    let application = adw::Application::builder()
        .application_id(APP_ID)
        .flags(gio::ApplicationFlags::HANDLES_OPEN)
        .build();
    let shared = App::new();
    let _ = shared.application.set(application.clone());

    launch::install(&application, &shared);
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
    launch::add_actions(application, shared);
    menus::install_accelerators(application);
    sources::start(shared);
    network_ui::start(shared);
    let on = shared.clone();
    shared.services.start(move || {
        network_ui::check_sign_ins(&on);
        downloads_ui::start(&on);
        sync_ui::at_start(&on);
    });
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
    // Kept for scripted walks: `gapplication action com.mecedric.StoryArc open-reader
    // "'/path/to/book.cbz'"` opens a file as a drop does.
    let on = shared.clone();
    let open_reader = gio::ActionEntry::builder("open-reader")
        .parameter_type(Some(glib::VariantTy::STRING))
        .activate(move |_: &adw::Application, _, parameter| {
            if let Some(path) = parameter.and_then(|value| value.get::<String>()) {
                launch::open_paths(&on, &[PathBuf::from(path)]);
            }
        })
        .build();
    // Kept for scripted walks beside `open-reader`: `gapplication action com.mecedric.StoryArc
    // add-network-source "'catalogue'"` presents the same sheet the sidebar's add menu does.
    let on = shared.clone();
    let add_network = gio::ActionEntry::builder("add-network-source")
        .parameter_type(Some(glib::VariantTy::STRING))
        .activate(move |_: &adw::Application, _, parameter| {
            let Some(window) = on.library.borrow().clone() else {
                return;
            };
            let name = parameter.and_then(|value| value.get::<String>());
            let action = match name.as_deref() {
                Some("share") => "win.add-share",
                Some("kavita") => "win.add-kavita",
                _ => "win.add-catalogue",
            };
            let _ = gtk::prelude::WidgetExt::activate_action(&window, action, None);
        })
        .build();
    // And `show-network-source "'0'"` opens the first network library's page, as its sidebar
    // row does.
    let on = shared.clone();
    let show_network = gio::ActionEntry::builder("show-network-source")
        .parameter_type(Some(glib::VariantTy::STRING))
        .activate(move |_: &adw::Application, _, parameter| {
            let index = parameter
                .and_then(|value| value.get::<String>())
                .and_then(|text| text.parse().ok())
                .unwrap_or(0);
            remote_browse::open(&on, index);
        })
        .build();
    // `library-action "'new-shelf'"` runs a window action of the library window, and
    // `show-shelf "'0'"` opens a shelf by its row in the sidebar.
    let on = shared.clone();
    let library_action = gio::ActionEntry::builder("library-action")
        .parameter_type(Some(glib::VariantTy::STRING))
        .activate(move |_: &adw::Application, _, parameter| {
            let (Some(window), Some(name)) = (
                on.library.borrow().clone(),
                parameter.and_then(|value| value.get::<String>()),
            ) else {
                return;
            };
            let _ = gtk::prelude::WidgetExt::activate_action(&window, &format!("win.{name}"), None);
        })
        .build();
    // `reader-action "'find'"` runs a window action of the reader window opened last, for the
    // walks: a wtype Control chord was not delivered under cage (task 4.11's walk).
    let on = shared.clone();
    let reader_action = gio::ActionEntry::builder("reader-action")
        .parameter_type(Some(glib::VariantTy::STRING))
        .activate(move |_: &adw::Application, _, parameter| {
            let (Some(window), Some(name)) = (
                on.readers
                    .borrow()
                    .last()
                    .map(|handle| handle.window.clone()),
                parameter.and_then(|value| value.get::<String>()),
            ) else {
                return;
            };
            let outcome =
                gtk::prelude::WidgetExt::activate_action(&window, &format!("win.{name}"), None);
            glib::g_message!(session::LOG_DOMAIN, "reader-action {name}: {outcome:?}");
        })
        .build();
    let on = shared.clone();
    let show_shelf = gio::ActionEntry::builder("show-shelf")
        .parameter_type(Some(glib::VariantTy::STRING))
        .activate(move |_: &adw::Application, _, parameter| {
            let index = parameter
                .and_then(|value| value.get::<String>())
                .and_then(|text| text.parse().ok())
                .unwrap_or(0);
            shelf_ui::activate_row(&on, index);
        })
        .build();
    application.add_action_entries([
        library_action,
        reader_action,
        show_shelf,
        quit,
        preferences,
        shortcuts,
        about,
        open_reader,
        add_network,
        show_network,
    ]);
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
    // A download in progress is the one thing a quit asks about: it pauses, and resumes at
    // the next launch (`desktop-experience`, No presence when the app is closed).
    if let (Some(prompt), Some(window)) =
        (shared.downloads.quit_prompt(), application.active_window())
    {
        let alert = adw::AlertDialog::new(Some(&prompt.title), Some(&prompt.body));
        alert.add_responses(&[
            ("cancel", &strings::tr("sources.rename.cancel", "Cancel")),
            ("quit", &strings::tr("menu.quit", "Quit")),
        ]);
        alert.set_response_appearance("quit", adw::ResponseAppearance::Suggested);
        alert.set_close_response("cancel");
        let (app, on) = (application.clone(), shared.clone());
        alert.connect_response(None, move |_, response| {
            if response == "quit" {
                finish_quit(&app, &on);
            }
        });
        alert.present(Some(&window));
        return;
    }
    finish_quit(application, shared);
}

fn finish_quit(application: &adw::Application, shared: &Shared) {
    shared.quitting.set(true);
    downloads_ui::pause_for_quit(shared);
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
    // The sync document is written once more when a position changed, for five seconds at
    // most, and the app quits whatever came of it.
    let _ = sync_ui::at_quit(shared);
    application.quit();
}

fn show_about(application: &adw::Application) {
    about::dialog(storyarc_core::version()).present(application.active_window().as_ref());
}

/// Launch, or a second launch: present the library, restoring every window the last
/// run left open when there is none yet. A first launch from one of the desktop entry's
/// static actions runs that action instead.
fn activate(shared: &Shared) {
    if let Some(action) = shared.launch_action.take() {
        launch::run(shared, action);
        return;
    }
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
    let names: Vec<String> = missing
        .iter()
        .map(|path| opening::name(std::path::Path::new(path)))
        .collect();
    let library = library_window::open(shared, &plan.library, &names);
    for (publication, reader) in readers {
        reader_window::open(shared, publication, reader.page, Some(reader.window));
    }
    let seen = about::after_launch(Some(&library), session::seen_version().as_deref());
    session::save_seen_version(&seen);
}
