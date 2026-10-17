//! The preferences that act on the network, the disk and the files the app writes (tasks
//! 3.17 to 3.19): the network libraries' rows, Storage (what each store uses and clearing it
//! on its own, the secret store's state, the metered rule), Sync (the folder the document
//! lives in) and Export diagnostics (shown in full, then a save dialog). The rules are
//! `storage_rules.rs`, `secret_state.rs`, `sync_rules.rs` and `diagnostic_export.rs`.

use std::path::PathBuf;

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::paths::StorageLocations;
use storyarc_core::secrets::{Secret, SecretKey};

use crate::app::Shared;
use crate::diagnostic_export::{self, Exported};
use crate::storage_rules::{self, Store};
use crate::strings::{tr, tr_args};
use crate::{downloads_ui, network_ui, secret_state, session, sync_ui};

fn locations(shared: &Shared) -> StorageLocations {
    shared
        .services
        .get()
        .map_or_else(StorageLocations::current, |s| s.locations.clone())
}

fn size(bytes: u64) -> String {
    glib::format_size(bytes).to_string()
}

/// The network libraries, one row each: its state in grey, and Remove after a
/// confirmation. Then the three ways to add one.
pub fn remote_rows(
    shared: &Shared,
    dialog: &adw::PreferencesDialog,
    group: &adw::PreferencesGroup,
) {
    for entry in shared.remote.entries.borrow().iter() {
        let state = entry
            .grey
            .clone()
            .unwrap_or_else(|| tr("sources.state.connected", "Available"));
        let row = adw::ActionRow::builder()
            .title(glib::markup_escape_text(&entry.record.name))
            .subtitle(glib::markup_escape_text(&state))
            .build();
        row.add_prefix(&gtk::Image::from_icon_name("network-server-symbolic"));
        let button = gtk::Button::builder()
            .label(tr("sources.remove", "Remove"))
            .valign(gtk::Align::Center)
            .css_classes(["destructive-action"])
            .build();
        let (on, id, name, parent) = (
            shared.clone(),
            entry.record.id.clone(),
            entry.record.name.clone(),
            dialog.downgrade(),
        );
        button.connect_clicked(move |button| {
            let alert = adw::AlertDialog::new(
                Some(&tr_args("sources.remove.title %s", "Remove %s?", &[&name])),
                Some(&tr(
                    "sources.remove.footer",
                    "Removing a library deletes what you downloaded from it and keeps your reading positions for 30 days.",
                )),
            );
            alert.add_responses(&[
                ("cancel", &tr("sources.rename.cancel", "Cancel")),
                ("remove", &tr("sources.remove", "Remove")),
            ]);
            alert.set_response_appearance("remove", adw::ResponseAppearance::Destructive);
            alert.set_close_response("cancel");
            let (on, id, parent) = (on.clone(), id.clone(), parent.clone());
            alert.connect_response(None, move |_, response| {
                if response == "remove" {
                    network_ui::remove(&on, &id);
                    if let Some(dialog) = parent.upgrade() {
                        dialog.close();
                    }
                }
            });
            alert.present(Some(button));
        });
        row.add_suffix(&button);
        group.add(&row);
    }
    for (label, action) in [
        (
            tr("sources.add.share", "A computer on your network"),
            "win.add-share",
        ),
        (
            tr("sources.add.catalogue", "Online library"),
            "win.add-catalogue",
        ),
        (tr("sources.add.kavita", "Kavita library"), "win.add-kavita"),
    ] {
        let row = adw::ActionRow::builder()
            .title(label)
            .activatable(true)
            .build();
        row.add_prefix(&gtk::Image::from_icon_name("list-add-symbolic"));
        let (on, close) = (shared.clone(), dialog.downgrade());
        row.connect_activated(move |_| {
            if let Some(dialog) = close.upgrade() {
                dialog.close();
            }
            if let Some(window) = on.library.borrow().clone() {
                gtk::prelude::WidgetExt::activate_action(&window, action, None).ok();
            }
        });
        group.add(&row);
    }
}

/// Storage: what each store uses and each can be cleared on its own.
pub fn storage_page(shared: &Shared) -> adw::PreferencesPage {
    let at = locations(shared);
    let group = adw::PreferencesGroup::builder()
        .title(tr("settings.storage", "Storage"))
        .name("storage")
        .description(tr(
            "storage.where",
            "StoryArc keeps its data in your own folders. Nothing here is synchronised between machines.",
        ))
        .build();
    if shared.downloads.full_disk() {
        group.set_description(Some(&storage_rules::full_disk_line()));
    }
    for store in Store::ALL {
        let folder = storage_rules::folder(&at, store);
        let row = adw::ActionRow::builder()
            .title(store.label())
            .subtitle(size(storage_rules::size_of(&folder)))
            .build();
        if store.clearable_by_a_tap() {
            let button = gtk::Button::builder()
                .label(tr("privacy.clear", "Clear"))
                .valign(gtk::Align::Center)
                .build();
            let (on, row_ref) = (shared.clone(), row.downgrade());
            button.connect_clicked(move |button| {
                clear(&on, store, folder.clone(), button, row_ref.clone())
            });
            row.add_suffix(&button);
        }
        group.add(&row);
    }
    let downloads = adw::PreferencesGroup::builder()
        .title(tr("sidebar.downloads", "Downloads"))
        .build();
    let metered = adw::SwitchRow::builder()
        .title(tr("downloads.unmetered", "Wait on a metered connection"))
        .subtitle(tr(
            "downloads.unmetered.note",
            "On a connection your system marks as metered, downloads you did not start by hand wait.",
        ))
        .active(shared.preferences().unmetered_only)
        .build();
    let on = shared.clone();
    metered.connect_active_notify(move |row| {
        let active = row.is_active();
        on.update_preferences(|p| p.unmetered_only = active);
        downloads_ui::policy_changed(&on);
    });
    downloads.add(&metered);
    let secrets = adw::PreferencesGroup::builder()
        .title(tr("settings.passwords", "Passwords"))
        .build();
    let line = shared.services.get().map_or_else(
        || {
            tr(
                "network.starting",
                "StoryArc is still starting. Try again in a moment.",
            )
        },
        |s| secret_state::status_line(&s.vault, s.is_flatpak()),
    );
    secrets.add(
        &adw::ActionRow::builder()
            .title(glib::markup_escape_text(&line))
            .css_classes(["dimmed"])
            .build(),
    );
    let page = adw::PreferencesPage::builder()
        .title(tr("settings.storage", "Storage"))
        .name("storage")
        .icon_name("drive-harddisk-symbolic")
        .build();
    page.add(&group);
    page.add(&downloads);
    page.add(&secrets);
    page.add(&sync_group(shared));
    page
}

fn clear(
    shared: &Shared,
    store: Store,
    folder: PathBuf,
    parent: &gtk::Button,
    row: glib::WeakRef<adw::ActionRow>,
) {
    let run = {
        let (on, folder) = (shared.clone(), folder);
        move || {
            let result = match store {
                Store::Downloads => downloads_ui::clear_all(&on, &folder),
                _ => storage_rules::clear(&folder),
            };
            if let Err(error) = result {
                on.toast(&storage_rules::failed_write_line(&error));
            }
            on.library_changed();
            if let Some(row) = row.upgrade() {
                row.set_subtitle(&size(storage_rules::size_of(&folder_of(&on, store))));
            }
        }
    };
    if store != Store::Downloads {
        run();
        return;
    }
    let alert = adw::AlertDialog::new(
        Some(&tr("downloads.clear.title", "Remove every download?")),
        Some(&tr(
            "downloads.clear.body",
            "This deletes the downloaded copies on this device and stops what is coming down. Your reading positions are kept, and each can be downloaded again.",
        )),
    );
    alert.add_responses(&[
        ("cancel", &tr("sources.rename.cancel", "Cancel")),
        ("clear", &tr("downloads.remove", "Remove download")),
    ]);
    alert.set_response_appearance("clear", adw::ResponseAppearance::Destructive);
    alert.set_close_response("cancel");
    alert.connect_response(None, move |_, response| {
        if response == "clear" {
            run();
        }
    });
    alert.present(Some(parent));
}

fn folder_of(shared: &Shared, store: Store) -> PathBuf {
    storage_rules::folder(&locations(shared), store)
}

/// Sync: the folder the document lives in, and what the last sync came to.
fn sync_group(shared: &Shared) -> adw::PreferencesGroup {
    let group = adw::PreferencesGroup::builder()
        .title(tr("sync.title", "Sync"))
        .description(tr(
            "sync.about",
            "Keep your reading positions, shelves and settings the same on all your devices, through a place you choose.",
        ))
        .build();
    let place = session::load_sync_folder();
    let row = adw::ActionRow::builder()
        .title(tr("sync.place", "Place"))
        .subtitle(glib::markup_escape_text(&place.as_ref().map_or_else(
            || tr("sync.status.idle", "Not synced yet"),
            |p| p.display().to_string(),
        )))
        .activatable(true)
        .build();
    let on = shared.clone();
    row.connect_activated(move |row| {
        let dialog = gtk::FileDialog::builder()
            .title(tr("sync.chooseFolder", "Choose a folder"))
            .modal(true)
            .build();
        let (on, row) = (on.clone(), row.downgrade());
        let parent = on.library.borrow().clone();
        dialog.select_folder(parent.as_ref(), None::<&gio::Cancellable>, move |result| {
            let Ok(folder) = result else { return };
            let Some(path) = folder.path() else { return };
            if on.sources.paths().contains(&path) {
                on.toast(&tr(
                    "sync.folderIsLibrary",
                    "This folder is one of your libraries. Choose another folder for sync.",
                ));
                return;
            }
            session::save_sync_folder(Some(&path));
            if let Some(row) = row.upgrade() {
                row.set_subtitle(&glib::markup_escape_text(&path.display().to_string()));
            }
            sync_ui::now(&on);
        });
    });
    group.add(&row);
    let status = shared.sync_line.borrow().clone();
    if !status.is_empty() {
        group.add(
            &adw::ActionRow::builder()
                .title(glib::markup_escape_text(&status))
                .css_classes(["dimmed"])
                .build(),
        );
    }
    if place.is_some() {
        let off = adw::ActionRow::builder()
            .title(tr("sync.turnOff", "Turn off sync"))
            .activatable(true)
            .build();
        let on = shared.clone();
        off.connect_activated(move |row| {
            session::save_sync_folder(None);
            row.set_sensitive(false);
            on.sync_line.borrow_mut().clear();
        });
        group.add(&off);
    }
    group
}

/// Export diagnostics: the text in full, then a save dialog. Cancelling writes nothing.
pub fn diagnostics_row(shared: &Shared) -> adw::ActionRow {
    let row = adw::ActionRow::builder()
        .title(diagnostic_export::title())
        .subtitle(tr(
            "diagnostics.note",
            "Shows everything first. Passwords, tokens and server names are removed.",
        ))
        .activatable(true)
        .build();
    let on = shared.clone();
    row.connect_activated(move |row| present_diagnostic(&on, row.upcast_ref()));
    row
}

fn diagnostic_text(shared: &Shared) -> String {
    let services = shared.services.get();
    let records = shared.remote.records();
    let held: Vec<Secret> = services
        .as_ref()
        .map(|s| {
            records
                .iter()
                .filter_map(|r| {
                    let key = SecretKey::for_source(&r.id, r.kind.secret_field());
                    s.vault.load(&key).ok().flatten()
                })
                .collect()
        })
        .unwrap_or_default();
    let secrets: Vec<&Secret> = held.iter().collect();
    let sources: Vec<(String, String)> = records
        .iter()
        .map(|r| (format!("{:?}", r.kind).to_lowercase(), r.address.clone()))
        .chain([(
            "folders".to_owned(),
            shared.sources.paths().len().to_string(),
        )])
        .collect();
    let lines: Vec<(&str, &str)> = sources
        .iter()
        .map(|(a, b)| (a.as_str(), b.as_str()))
        .collect();
    diagnostic_export::report(
        storyarc_core::version(),
        services.is_some_and(|s| s.is_flatpak()),
        &lines,
        &secrets,
    )
}

fn present_diagnostic(shared: &Shared, parent: &gtk::Widget) {
    let text = diagnostic_text(shared);
    let view = gtk::TextView::builder()
        .editable(false)
        .monospace(true)
        .wrap_mode(gtk::WrapMode::WordChar)
        .left_margin(12)
        .right_margin(12)
        .top_margin(12)
        .build();
    view.buffer().set_text(&text);
    let save = gtk::Button::builder()
        .label(tr("diagnostics.save", "Save…"))
        .css_classes(["suggested-action"])
        .build();
    let header = adw::HeaderBar::new();
    header.pack_end(&save);
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);
    toolbar.set_content(Some(&gtk::ScrolledWindow::builder().child(&view).build()));
    let dialog = adw::Dialog::builder()
        .title(diagnostic_export::title())
        .content_width(560)
        .content_height(520)
        .child(&toolbar)
        .build();
    let (on, weak) = (shared.clone(), dialog.downgrade());
    save.connect_clicked(move |_| {
        let Some(dialog) = weak.upgrade() else { return };
        let chooser = gtk::FileDialog::builder()
            .title(diagnostic_export::title())
            .initial_name("storyarc-diagnostic.txt")
            .modal(true)
            .build();
        let (on, text, weak) = (on.clone(), text.clone(), dialog.downgrade());
        let window = dialog
            .root()
            .and_then(|root| root.downcast::<gtk::Window>().ok());
        chooser.save(window.as_ref(), None::<&gio::Cancellable>, move |result| {
            let chosen = result.ok().and_then(|file| file.path());
            match diagnostic_export::write(chosen.as_deref(), &text) {
                Exported::Written(path) => {
                    if let Some(dialog) = weak.upgrade() {
                        dialog.close();
                    }
                    on.toast(&tr_args(
                        "diagnostics.saved %s",
                        "Saved to %s",
                        &[&path.display()],
                    ));
                }
                // Cancelled: nothing was written, and the text stays only in this dialog.
                Exported::Cancelled => {}
                Exported::CannotWrite { message, .. } => {
                    let alert = adw::AlertDialog::new(
                        Some(&tr("diagnostics.cannotWrite.title", "Could not save")),
                        Some(&message),
                    );
                    alert.add_response(
                        "ok",
                        &tr("diagnostics.chooseAnother", "Choose another place"),
                    );
                    alert.present(weak.upgrade().as_ref());
                }
            }
        });
    });
    dialog.present(Some(parent));
}
