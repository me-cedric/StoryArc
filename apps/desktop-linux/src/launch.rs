//! The GTK side of opening files (task 2.30): the application claims the files the
//! desktop entry declares (`HANDLES_OPEN`), so a double click, Open With and the command
//! line reach the running instance through `GApplication`; windows take dropped files;
//! the Open File dialog goes through the portal; each opened file is recorded with
//! `GtkRecentManager`; and the entry's static actions arrive as command-line options.
//! What to open is `opening.rs`.

use std::ops::ControlFlow;
use std::path::{Path, PathBuf};

use adw::prelude::*;
use gtk::{gdk, gio, glib};

use crate::app::Shared;
use crate::opening::{Kind, LaunchAction, OpenPlan};
use crate::publication::Publication;
use crate::session;
use crate::windows::Open;
use crate::{library_window, portal, reader_window, sources};

/// The types the desktop entry declares; the Open File dialog offers the same.
const COMIC_TYPES: [&str; 5] = [
    "application/vnd.comicbook+zip",
    "application/x-cbz",
    "application/vnd.comicbook-rar",
    "application/x-cbr",
    "application/x-cbt",
];
const COMIC_PATTERNS: [&str; 3] = ["*.cbz", "*.cbr", "*.cbt"];

/// Wires the open signal, the command-line options of the entry's static actions and
/// the application actions they run.
pub fn install(application: &adw::Application, shared: &Shared) {
    for action in LaunchAction::ALL {
        application.add_main_option(
            action.name(),
            glib::Char::from(0u8),
            glib::OptionFlags::NONE,
            glib::OptionArg::None,
            action.description(),
            None,
        );
    }
    let on = shared.clone();
    application.connect_handle_local_options(move |application, options| {
        let Some(action) = LaunchAction::ALL
            .into_iter()
            .find(|action| options.contains(action.name()))
        else {
            return ControlFlow::Continue(());
        };
        if application.register(None::<&gio::Cancellable>).is_err() {
            return ControlFlow::Continue(());
        }
        if application.is_remote() {
            // A second launch hands the action to the running instance and ends.
            application.activate_action(action.name(), None);
            return ControlFlow::Break(glib::ExitCode::SUCCESS);
        }
        // The first launch runs it in place of restoring the session.
        on.launch_action.set(Some(action));
        ControlFlow::Continue(())
    });
    let on = shared.clone();
    application.connect_open(move |_, files, _| {
        let paths: Vec<PathBuf> = files
            .iter()
            .map(|file| file.path().unwrap_or_else(|| PathBuf::from(file.uri())))
            .collect();
        open_paths(&on, &paths);
    });
}

/// The application actions the entry's static actions run.
pub fn add_actions(application: &adw::Application, shared: &Shared) {
    for action in LaunchAction::ALL {
        let simple = gio::SimpleAction::new(action.name(), None);
        let on = shared.clone();
        simple.connect_activate(move |_, _| run(&on, action));
        application.add_action(&simple);
    }
}

/// Runs a static action: Continue Reading opens the publication read last, and Library
/// and Downloads bring the library window forward on that destination.
pub fn run(shared: &Shared, action: LaunchAction) {
    match action {
        LaunchAction::ContinueReading => {
            let last = shared
                .progress_store()
                .recent(1)
                .ok()
                .and_then(|records| records.into_iter().next())
                .and_then(|record| record.identity.normalized_path);
            match last {
                Some(path) if Path::new(&path).exists() => open_paths(shared, &[path.into()]),
                _ => show_library(shared, LaunchAction::Library),
            }
        }
        other => show_library(shared, other),
    }
}

/// Opens what was handed over: each file in its own reader window up to the limit, a
/// folder offered as a library, and every refusal named in grey in the library.
pub fn open_paths(shared: &Shared, paths: &[PathBuf]) {
    let plan = OpenPlan::of(paths, Kind::of);
    let mut notes = plan.unreachable.clone();
    for path in &plan.open {
        if let Err(reason) = open_publication(shared, path) {
            notes.push(reason);
        }
    }
    for folder in &plan.folders {
        offer_folder(shared, folder);
    }
    notes.extend(plan.left_over_note());
    if !notes.is_empty() {
        notify(shared, &notes);
    }
}

/// Opens a publication in a reader window, or brings forward the one that reads it, and
/// records it with the desktop's recent files. The error names the file and the reason.
pub fn open_publication(shared: &Shared, path: &Path) -> Result<(), String> {
    let id = path.to_string_lossy().into_owned();
    if let Open::Present(_) = shared.open(&id) {
        if let Some(window) = shared.reader_for(&id) {
            window.present();
        }
        return Ok(());
    }
    let publication = Publication::open(path)?;
    let store = shared.progress_store();
    let page = session::CoreProgress::page(&store, &publication.record.identity).unwrap_or(0);
    reader_window::open(shared, publication, page, None);
    shared.save_session();
    record_recent(path);
    Ok(())
}

/// `desktop-experience`, Recent publications on Linux: file managers and file dialogs
/// list what the reader opened. A file that is gone later drops out of their lists.
fn record_recent(path: &Path) {
    let uri = gio::File::for_path(path).uri();
    gtk::RecentManager::default().add_item(&uri);
}

/// A window takes files dropped on it. Text, or an image that is not a file, is not a
/// file list, so the target never accepts it and nothing happens.
pub fn install_drop(widget: &gtk::Widget, shared: &Shared) {
    let target = gtk::DropTarget::new(gdk::FileList::static_type(), gdk::DragAction::COPY);
    let weak = std::rc::Rc::downgrade(shared);
    target.connect_drop(move |_, value, _, _| {
        let Ok(list) = value.get::<gdk::FileList>() else {
            return false;
        };
        let paths: Vec<PathBuf> = list.files().iter().filter_map(|file| file.path()).collect();
        let weak = weak.clone();
        // Windows open after the drop has finished, never inside its handler.
        glib::idle_add_local_once(move || {
            if let Some(shared) = weak.upgrade() {
                open_paths(&shared, &paths);
            }
        });
        true
    });
    widget.add_controller(target);
}

/// Open File: the system's chooser through the portal, several files at once.
pub fn choose_files(shared: &Shared, parent: &gtk::Window) {
    let filter = gtk::FileFilter::new();
    filter.set_name(Some("Comics"));
    for kind in COMIC_TYPES {
        filter.add_mime_type(kind);
    }
    for pattern in COMIC_PATTERNS {
        filter.add_pattern(pattern);
    }
    let filters = gio::ListStore::new::<gtk::FileFilter>();
    filters.append(&filter);
    let dialog = gtk::FileDialog::builder()
        .title("Open File")
        .modal(true)
        .filters(&filters)
        .build();
    let on = shared.clone();
    dialog.open_multiple(
        Some(parent),
        None::<&gio::Cancellable>,
        move |result| match result {
            Ok(files) => {
                let paths: Vec<PathBuf> = (0..files.n_items())
                    .filter_map(|index| files.item(index).and_downcast::<gio::File>())
                    .filter_map(|file| file.path())
                    .collect();
                open_paths(&on, &paths);
            }
            Err(error) => portal::chooser_failed(&on, &error),
        },
    );
}

/// Brings the library window forward, building it from the saved session when no
/// library window is open.
pub fn show_library(shared: &Shared, action: LaunchAction) {
    let open = shared.library.borrow().clone();
    let window = match open.filter(|window| window.is_visible()) {
        Some(window) => window,
        None => {
            let Some(display) = gdk::Display::default() else {
                return;
            };
            let plan = session::restore(&display, Publication::is_reachable);
            library_window::open(shared, &plan.library, &[])
        }
    };
    library_window::show(shared, action);
    window.present();
}

/// Names each refusal in grey where the library shows what could not be opened, opening
/// the library window first when the reader opened a file with no window up.
pub fn notify(shared: &Shared, notes: &[String]) {
    if shared.library_toasts.borrow().is_none() {
        show_library(shared, LaunchAction::Library);
    }
    for note in notes {
        shared.toast(note);
    }
}

/// A folder handed over is offered as a folder library (task 2.31).
fn offer_folder(shared: &Shared, folder: &Path) {
    sources::offer(shared, folder);
}
