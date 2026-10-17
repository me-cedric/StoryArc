//! The preferences dialog (tasks 2.35 and 2.35e): `AdwPreferencesDialog` with search over
//! an Appearance page and a Reading page. Every change goes through
//! `App::update_preferences`, which writes the file and applies the change to the theme
//! and to every open reader at once.
//!
//! The Accent row offers the System choice only where the system reports an accent, which
//! the libadwaita 1.5 floor never does through `AdwStyleManager`; `portal.rs` reads it from
//! the settings portal instead, so the row appears on any session whose portal offers one
//! and is absent, with the brand colour kept, on one that does not.

use adw::prelude::*;

use crate::app::Shared;
use crate::preferences_pages;
use crate::settings::{Accent, Appearance, Fit, Label, Layout};
use crate::strings::tr;
use crate::theme::Theme;

fn text((key, english): Label) -> String {
    match key {
        Some(key) => tr(key, english),
        None => english.to_owned(),
    }
}

fn choice_row<T: Copy + PartialEq + 'static>(
    title: &str,
    choices: Vec<T>,
    label: fn(T) -> Label,
    current: T,
    on_change: impl Fn(T) + 'static,
) -> adw::ComboRow {
    let names: Vec<String> = choices.iter().map(|choice| text(label(*choice))).collect();
    let names: Vec<&str> = names.iter().map(String::as_str).collect();
    let row = adw::ComboRow::builder()
        .title(title)
        .model(&gtk::StringList::new(&names))
        .selected(
            choices
                .iter()
                .position(|choice| *choice == current)
                .unwrap_or(0) as u32,
        )
        .build();
    row.connect_selected_notify(move |row| {
        if let Some(choice) = choices.get(row.selected() as usize) {
            on_change(*choice);
        }
    });
    row
}

/// Presents the one preferences dialog over `parent`, or presents it again.
pub fn present(shared: &Shared, parent: Option<&gtk::Window>) {
    if let Some(dialog) = shared.preferences_dialog.borrow().as_ref() {
        dialog.present(parent);
        return;
    }
    let preferences = shared.preferences();

    let appearance = adw::PreferencesGroup::builder()
        .title(tr("settings.appearance", "Appearance"))
        .build();
    if !Theme::system_states_appearance() {
        appearance.set_description(Some(&tr(
            "settings.appearance.noPortal",
            "This session does not state its appearance, so System draws light.",
        )));
    }
    let on = shared.clone();
    appearance.add(&choice_row(
        &tr("settings.appearance", "Appearance"),
        Appearance::ALL.to_vec(),
        Appearance::label,
        preferences.appearance,
        move |choice| on.update_preferences(|p| p.appearance = choice),
    ));
    let system_accent = shared.system_accent.get();
    // Guarded at run time: absent, not disabled, where the system offers no accent.
    let accents = Accent::choices(system_accent);
    if accents.len() > 1 {
        let on = shared.clone();
        appearance.add(&choice_row(
            &tr("settings.accent", "Accent"),
            accents,
            Accent::label,
            preferences.accent,
            move |choice| on.update_preferences(|p| p.accent = choice),
        ));
    }

    let reading = adw::PreferencesGroup::builder()
        .title(tr("settings.reading", "Reading"))
        .build();
    let on = shared.clone();
    reading.add(&choice_row(
        &tr("settings.layout", "Page layout"),
        Layout::ALL.to_vec(),
        Layout::label,
        preferences.layout,
        move |choice| on.update_preferences(|p| p.layout = choice),
    ));
    let on = shared.clone();
    reading.add(&choice_row(
        &tr("settings.fit", "Fit"),
        Fit::ALL.to_vec(),
        Fit::label,
        preferences.fit,
        move |choice| on.update_preferences(|p| p.fit = choice),
    ));
    let zones = adw::SwitchRow::builder()
        .title(tr(
            "settings.clickZones",
            "Turn pages by clicking the edges",
        ))
        .active(preferences.click_zones)
        .build();
    let on = shared.clone();
    zones.connect_active_notify(move |row| {
        let active = row.is_active();
        on.update_preferences(|p| p.click_zones = active);
    });
    reading.add(&zones);

    let appearance_page = adw::PreferencesPage::builder()
        .title(tr("settings.appearance", "Appearance"))
        .icon_name("preferences-desktop-appearance-symbolic")
        .build();
    appearance_page.add(&appearance);
    let reading_page = adw::PreferencesPage::builder()
        .title(tr("settings.reading", "Reading"))
        .icon_name("view-paged-symbolic")
        .build();
    reading_page.add(&reading);

    let dialog = adw::PreferencesDialog::builder()
        .title(tr("settings.title", "Settings"))
        .search_enabled(true)
        .build();
    reading_page.add(&preferences_pages::reset_group(shared, &dialog));
    dialog.add(&preferences_pages::libraries_page(shared, &dialog));
    dialog.add(&appearance_page);
    dialog.add(&reading_page);
    dialog.add(&crate::storage_ui::storage_page(shared));
    dialog.add(&preferences_pages::privacy_page(shared));
    let on = shared.clone();
    dialog.connect_closed(move |_| {
        on.preferences_dialog.borrow_mut().take();
    });
    *shared.preferences_dialog.borrow_mut() = Some(dialog.clone());
    dialog.present(parent);
}
