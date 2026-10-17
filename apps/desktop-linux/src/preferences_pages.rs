//! The preferences pages that act rather than choose (`settings-and-about`): Libraries,
//! where each folder's state and what can be done about it live (`navigation-shell`,
//! Reaching a source's configuration); Privacy, which states the app's posture and
//! clears the reading history; and the reset of the preferences themselves.

use std::path::{Path, PathBuf};

use adw::prelude::*;
use gtk::{gio, glib};

use crate::app::Shared;
use crate::folders::Access;
use crate::session::{self, LOG_DOMAIN};
use crate::settings::Preferences;
use crate::sources;
use crate::strings::{tr, tr_args, tr_plural};

/// The folder libraries, one row each: its state, Choose Again when access was
/// withdrawn, Show in Folder, and Remove after a confirmation.
pub fn libraries_page(shared: &Shared, dialog: &adw::PreferencesDialog) -> adw::PreferencesPage {
    let group = adw::PreferencesGroup::builder()
        .title(tr("settings.sources", "Your libraries"))
        .build();
    let paths = shared.sources.paths();
    if paths.is_empty() {
        group.set_description(Some(&tr("settings.sources.none", "No libraries yet")));
    }
    for ((name, access, not_live), path) in shared.sources.summary().into_iter().zip(paths) {
        let mut state = match access {
            Access::Readable => tr("sources.state.connected", "Available"),
            other => other.note().unwrap_or_default().to_owned(),
        };
        if let Some(note) = not_live {
            state = format!("{state} · {note}");
        }
        let row = adw::ActionRow::builder()
            .title(&name)
            .subtitle(&state)
            .use_markup(false)
            .build();
        if access == Access::Withdrawn {
            let again = gtk::Button::builder()
                .label(tr("library.repick", "Choose Again"))
                .valign(gtk::Align::Center)
                .build();
            let on = shared.clone();
            let choose = dialog.downgrade();
            let index = on.sources.paths().iter().position(|p| *p == path);
            again.connect_clicked(move |_| {
                if let (Some(index), Some(window)) = (index, on.library.borrow().clone()) {
                    if let Some(dialog) = choose.upgrade() {
                        dialog.close();
                    }
                    sources::choose_again(&on, window.upcast_ref(), index);
                }
            });
            row.add_suffix(&again);
        }
        row.add_suffix(&show_in_folder(&path));
        row.add_suffix(&remove_button(shared, dialog, &path, &name));
        group.add(&row);
    }
    let add = adw::ActionRow::builder()
        .title(tr("library.addSource", "Add Folder…"))
        .activatable(true)
        .build();
    add.add_prefix(&gtk::Image::from_icon_name("list-add-symbolic"));
    let on = shared.clone();
    let close = dialog.downgrade();
    add.connect_activated(move |_| {
        if let Some(dialog) = close.upgrade() {
            dialog.close();
        }
        if let Some(window) = on.library.borrow().clone() {
            sources::choose(&on, window.upcast_ref(), None);
        }
    });
    group.add(&add);
    let page = adw::PreferencesPage::builder()
        .title(tr("settings.sources", "Your libraries"))
        .icon_name("folder-symbolic")
        .build();
    page.add(&group);
    page
}

fn show_in_folder(path: &Path) -> gtk::Button {
    let button = gtk::Button::builder()
        .icon_name("folder-open-symbolic")
        .tooltip_text(tr("detail.showInFolder", "Show in folder"))
        .valign(gtk::Align::Center)
        .css_classes(["flat"])
        .build();
    button.update_property(&[gtk::accessible::Property::Label(&tr(
        "detail.showInFolder",
        "Show in folder",
    ))]);
    let path = path.to_path_buf();
    button.connect_clicked(move |_| {
        gtk::FileLauncher::new(Some(&gio::File::for_path(&path))).launch(
            gtk::Window::NONE,
            None::<&gio::Cancellable>,
            |_| {},
        );
    });
    button
}

/// Removing a folder is the one red choice here: it names the folder and what leaves.
fn remove_button(
    shared: &Shared,
    dialog: &adw::PreferencesDialog,
    path: &Path,
    name: &str,
) -> gtk::Button {
    let button = gtk::Button::builder()
        .label(tr("sources.remove", "Remove"))
        .valign(gtk::Align::Center)
        .css_classes(["destructive-action"])
        .build();
    let on = shared.clone();
    let parent = dialog.downgrade();
    let path: PathBuf = path.to_path_buf();
    let name = name.to_owned();
    button.connect_clicked(move |button| {
        let count = on.sources.count_at(&path);
        let alert = adw::AlertDialog::new(
            Some(&tr_args("sources.remove.title %s", "Remove %s?", &[&name])),
            Some(&format!(
                "{} {}",
                tr_plural(
                    "sources.remove.body %d",
                    "This removes %d title from your library.",
                    "This removes %d titles from your library.",
                    count as u64
                ),
                tr(
                    "sources.remove.kept",
                    "The files stay where they are, and so do your reading positions."
                )
            )),
        );
        alert.add_responses(&[
            ("cancel", &tr("sources.rename.cancel", "Cancel")),
            ("remove", &tr("sources.remove", "Remove")),
        ]);
        alert.set_response_appearance("remove", adw::ResponseAppearance::Destructive);
        alert.set_close_response("cancel");
        let on = on.clone();
        let path = path.clone();
        let parent = parent.clone();
        alert.connect_response(None, move |_, response| {
            if response == "remove" {
                sources::remove(&on, &path);
                if let Some(dialog) = parent.upgrade() {
                    dialog.close();
                }
            }
        });
        alert.present(Some(button));
    });
    button
}

/// Privacy: what the app does and does not do, and the reading history, cleared after a
/// confirmation that says what goes, what stays, and how much space it frees.
pub fn privacy_page(shared: &Shared) -> adw::PreferencesPage {
    let posture = adw::PreferencesGroup::builder()
        .title(tr("settings.privacy", "Privacy"))
        .description(format!(
            "{} {}",
            tr(
                "privacy.statement",
                "StoryArc has no account, no backend, no analytics and no crash reporting."
            ),
            tr(
                "privacy.sources",
                "Data leaves this device only to the libraries you set up yourself."
            )
        ))
        .build();
    let history = adw::ActionRow::builder()
        .title(history_title(shared))
        .subtitle(tr(
            "privacy.history.note",
            "Where you stopped in everything you have opened.",
        ))
        .build();
    let clear = gtk::Button::builder()
        .label(tr("privacy.clear", "Clear"))
        .valign(gtk::Align::Center)
        .css_classes(["destructive-action"])
        .build();
    let on = shared.clone();
    let row = history.downgrade();
    clear.connect_clicked(move |button| confirm_clear_history(&on, button, row.clone()));
    history.add_suffix(&clear);
    posture.add(&history);
    let page = adw::PreferencesPage::builder()
        .title(tr("settings.privacy", "Privacy"))
        .icon_name("security-high-symbolic")
        .build();
    page.add(&posture);
    page
}

/// "Reading history · 12 titles · 48 kB": what clearing removes and the space it frees.
fn history_title(shared: &Shared) -> String {
    let store = shared.progress_store();
    let titles = store.recent(usize::MAX).map_or(0, |records| records.len());
    let size = glib::format_size(store.store().size_on_disk());
    tr_args(
        "privacy.history %s",
        "Reading history · %s",
        &[&format!(
            "{} · {size}",
            tr_plural("shelves.count %d", "%d title", "%d titles", titles as u64)
        )],
    )
}

fn confirm_clear_history(
    shared: &Shared,
    parent: &gtk::Button,
    row: glib::WeakRef<adw::ActionRow>,
) {
    let alert = adw::AlertDialog::new(
        Some(&tr("privacy.clear.history", "Clear reading history")),
        Some(&format!(
            "{} {}",
            tr(
                "privacy.clear.history.body",
                "Every book and comic goes back to its first page. Your files, your libraries and your settings are not affected."
            ),
            tr(
                "privacy.clear.history.serverNote",
                "Progress kept on a server you read from is not changed."
            )
        )),
    );
    alert.add_responses(&[
        ("cancel", &tr("sources.rename.cancel", "Cancel")),
        ("clear", &tr("privacy.clear", "Clear")),
    ]);
    alert.set_response_appearance("clear", adw::ResponseAppearance::Destructive);
    alert.set_close_response("cancel");
    let on = shared.clone();
    alert.connect_response(None, move |_, response| {
        if response != "clear" {
            return;
        }
        clear_history(&on);
        if let Some(row) = row.upgrade() {
            row.set_title(&history_title(&on));
        }
    });
    alert.present(Some(parent));
}

/// Forgets every position, and removes the app's entries from the desktop's recent
/// files, at once (`desktop-experience`, Clearing the history). Nothing new is written
/// there until a publication is opened.
pub fn clear_history(shared: &Shared) {
    if let Err(error) = session::forget_history(&shared.progress_store()) {
        glib::g_warning!(LOG_DOMAIN, "Could not clear the reading history: {error}");
    }
    let manager = gtk::RecentManager::default();
    let ours = [glib::application_name(), glib::prgname()]
        .into_iter()
        .flatten()
        .map(|name| name.to_string())
        .collect::<Vec<_>>();
    for info in manager.items() {
        let mine = ours.iter().any(|name| info.has_application(name));
        if mine && let Err(error) = manager.remove_item(&info.uri()) {
            glib::g_warning!(LOG_DOMAIN, "Could not forget a recent file: {error}");
        }
    }
    shared.library_changed();
}

/// Reset settings: the preferences go back to their defaults, after a confirmation that
/// says the libraries, downloads and reading progress are not affected.
pub fn reset_group(shared: &Shared, dialog: &adw::PreferencesDialog) -> adw::PreferencesGroup {
    let group = adw::PreferencesGroup::new();
    let row = adw::ActionRow::builder()
        .title(tr("settings.reset", "Reset settings"))
        .activatable(true)
        .build();
    let on = shared.clone();
    let parent = dialog.downgrade();
    row.connect_activated(move |row| {
        let alert = adw::AlertDialog::new(
            Some(&tr("settings.reset", "Reset settings")),
            Some(&tr(
                "settings.reset.body",
                "Appearance, reading preferences and the defaults for new series go back to how they started. Your libraries, downloads, reading progress and the themes you chose while reading are not affected.",
            )),
        );
        alert.add_responses(&[
            ("cancel", &tr("sources.rename.cancel", "Cancel")),
            ("reset", &tr("settings.reset.confirm", "Reset")),
        ]);
        alert.set_response_appearance("reset", adw::ResponseAppearance::Destructive);
        alert.set_close_response("cancel");
        let on = on.clone();
        let parent = parent.clone();
        alert.connect_response(None, move |_, response| {
            if response != "reset" {
                return;
            }
            on.update_preferences(|preferences| *preferences = Preferences::default());
            // The rows show the old values: the dialog closes so the next one reads anew.
            if let Some(dialog) = parent.upgrade() {
                dialog.close();
            }
        });
        alert.present(Some(row));
    });
    group.add(&row);
    group
}
