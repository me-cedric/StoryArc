//! The GTK side of the command table (task 2.26): the accelerators, the actions a window
//! does not implement (shown disabled, never removed), the header-bar menus and the
//! Keyboard Shortcuts dialog. The table is `commands.rs`; nothing here decides which
//! command exists or which key it has.

use adw::prelude::*;
use gtk::gio;

use crate::commands::{self, Command, Place, Scope};
use crate::strings::tr;

/// The label a command shows, in the session's language where the catalogue has one.
pub fn label(command: &Command) -> String {
    match command.label_key {
        Some(key) => tr(key, command.label),
        None => command.label.to_owned(),
    }
}

/// Registers every accelerator of the table on the application. Page keys without a
/// modifier are left to the reader's key controller (`Command::registered_accels`).
pub fn install_accelerators(app: &adw::Application) {
    for command in commands::COMMANDS {
        let accels = command.registered_accels();
        if !accels.is_empty() {
            app.set_accels_for_action(command.action, accels);
        }
    }
}

/// Adds a disabled action for each `win.` command that applies in `scope` and that the
/// window does not implement, so its menu entry stays and reads grey (`desktop-experience`,
/// A command that does not apply). The window adds its own actions after this call.
pub fn add_disabled_actions(window: &impl IsA<gio::ActionMap>, scope: Scope, implemented: &[&str]) {
    for command in commands::for_window(scope) {
        let Some(name) = command.action.strip_prefix("win.") else {
            continue;
        };
        if implemented.contains(&command.action) {
            continue;
        }
        let action = gio::SimpleAction::new(name, None);
        action.set_enabled(false);
        window.add_action(&action);
    }
}

/// The primary menu: the commands the table places there, then About.
pub fn primary_menu() -> gio::Menu {
    let menu = gio::Menu::new();
    let section = gio::Menu::new();
    for command in commands::in_place(Place::PrimaryMenu) {
        section.append(Some(&label(command)), Some(command.action));
    }
    menu.append_section(None, &section);
    let about = gio::Menu::new();
    about.append(
        Some(&tr("settings.about", "About StoryArc")),
        Some("app.about"),
    );
    menu.append_section(None, &about);
    menu
}

/// The reader's menu and its context menu: the commands the table places in the
/// reader menu. `note` is appended to the full-screen entry when the compositor
/// refused full screen, so the grey entry says why.
pub fn reader_menu(menu: &gio::Menu, full_screen_note: Option<&str>) {
    menu.remove_all();
    let section = gio::Menu::new();
    for command in commands::in_place(Place::ReaderMenu) {
        let mut text = label(command);
        if command.action == "win.fullscreen"
            && let Some(note) = full_screen_note
        {
            text = format!("{text} ({note})");
        }
        section.append(Some(&text), Some(command.action));
    }
    menu.append_section(None, &section);
    let rest = gio::Menu::new();
    rest.append(
        Some(&tr("settings.title", "Settings…")),
        Some("app.preferences"),
    );
    rest.append(
        Some(&tr("shortcuts.title", "Keyboard Shortcuts")),
        Some("app.shortcuts"),
    );
    menu.append_section(None, &rest);
}

/// The Keyboard Shortcuts dialog: one `AdwDialog` listing every command that has a key,
/// grouped as the table groups them. Built from the table, so it cannot drift from the
/// accelerators. (`AdwShortcutsDialog` needs libadwaita 1.8; the floor is 1.5.)
pub fn shortcuts_dialog() -> adw::Dialog {
    let page = adw::PreferencesPage::new();
    for (group, commands) in commands::shortcut_sections() {
        let section = adw::PreferencesGroup::builder()
            .title(group_title(group))
            .build();
        for command in commands {
            let row = adw::ActionRow::builder().title(label(command)).build();
            let keys = gtk::ShortcutLabel::new(&command.accels.join(" "));
            keys.set_valign(gtk::Align::Center);
            row.add_suffix(&keys);
            section.add(&row);
        }
        page.add(&section);
    }
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&adw::HeaderBar::new());
    toolbar.set_content(Some(&page));
    adw::Dialog::builder()
        .title(tr("shortcuts.title", "Keyboard Shortcuts"))
        .content_width(480)
        .content_height(560)
        .child(&toolbar)
        .build()
}

fn group_title(group: commands::Group) -> String {
    match group {
        commands::Group::General => tr("shortcuts.general", "General"),
        commands::Group::Library => tr("shortcuts.library", "Library"),
        commands::Group::Reader => tr("shortcuts.reader", "Reader"),
        commands::Group::Player => tr("shortcuts.player", "Player"),
    }
}
