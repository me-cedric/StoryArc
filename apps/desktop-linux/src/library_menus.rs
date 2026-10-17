//! The library header bar's menus (task 2.35b, `library-browsing`, The controls that
//! change the view are grouped): View holds the layout and the grouping, Filter the
//! kind of file, the reading state and the folder with one action that clears them all,
//! and Sort the ordering. Each button names itself: the filter button counts what is
//! active and the sort button reads as an ordering ("Sort: Title"), so a sort cannot be
//! taken for a filter.

use adw::prelude::*;
use gtk::{gio, glib};

use crate::app::Shared;
use crate::library::entry::Format;
use crate::library::query::{QueryState, ReadState, Sort};
use crate::strings::{tr, tr_plural};

pub const FORMATS: [(&str, Option<Format>); 5] = [
    ("any", None),
    ("cbz", Some(Format::Cbz)),
    ("cbr", Some(Format::Cbr)),
    ("cbt", Some(Format::Cbt)),
    ("folder", Some(Format::Folder)),
];

/// Reading states: the target, the catalogue key and the English text.
pub const STATES: [(&str, &str, &str, Option<ReadState>); 4] = [
    ("any", "library.filter.readState", "Read or unread", None),
    (
        "unread",
        "library.readState.unread",
        "Unread",
        Some(ReadState::Unread),
    ),
    (
        "reading",
        "library.readState.inProgress",
        "In progress",
        Some(ReadState::Reading),
    ),
    (
        "finished",
        "library.readState.finished",
        "Finished",
        Some(ReadState::Finished),
    ),
];

pub const SORTS: [(&str, &str, &str, Sort); 4] = [
    ("title", "library.sort.title", "Title", Sort::Title),
    ("series", "library.sort.series", "Series", Sort::Series),
    (
        "date-added",
        "library.sort.dateAdded",
        "Date added",
        Sort::DateAdded,
    ),
    (
        "last-read",
        "library.sort.lastRead",
        "Last read",
        Sort::LastRead,
    ),
];

/// The target the folder filter uses for every folder.
pub const ANY_FOLDER: &str = "";

/// What the Sort button says: the ordering, named as one.
pub fn sort_label(sort: Sort) -> String {
    let name = SORTS
        .iter()
        .find(|(_, _, _, candidate)| *candidate == sort)
        .map_or_else(String::new, |(_, key, english, _)| tr(key, english));
    format!("{}: {name}", tr("library.sort", "Sort"))
}

/// What the Filter button says: the word, and how many filters are active.
pub fn filter_label(state: &QueryState) -> String {
    match state.filters.active_count() {
        0 => tr("library.filter", "Filter"),
        count => format!("{} · {count}", tr("library.filter", "Filter")),
    }
}

/// The filter button's accessible name, which says the count in words.
pub fn filter_description(state: &QueryState) -> String {
    match state.filters.active_count() {
        0 => tr("library.filter", "Filter"),
        count => tr_plural(
            "library.filter.active %d",
            "%d filter active",
            "%d filters active",
            count as u64,
        ),
    }
}

pub fn view_menu() -> gio::Menu {
    let menu = gio::Menu::new();
    let layout = gio::Menu::new();
    layout.append(
        Some(&tr("library.layout.grid", "Grid")),
        Some("win.layout::grid"),
    );
    layout.append(
        Some(&tr("library.layout.list", "List")),
        Some("win.layout::list"),
    );
    menu.append_section(Some(&tr("library.layout", "Show as")), &layout);
    let grouping = gio::Menu::new();
    grouping.append(
        Some(&tr("library.grouping.series", "Series")),
        Some("win.grouping::series"),
    );
    grouping.append(
        Some(&tr("library.grouping.issues", "Issues")),
        Some("win.grouping::issues"),
    );
    menu.append_section(Some(&tr("library.grouping", "Grouping")), &grouping);
    menu
}

/// The filter menu, with one entry per folder library.
pub fn filter_menu(folders: &[String]) -> gio::Menu {
    let menu = gio::Menu::new();
    let formats = gio::Menu::new();
    for (target, format) in FORMATS {
        let label = format.map_or_else(
            || tr("library.filter.format", "Kind of file"),
            |format| format.display_name().to_owned(),
        );
        formats.append(Some(&label), Some(&format!("win.filter-format::{target}")));
    }
    menu.append_section(Some(&tr("library.filter.format", "Kind of file")), &formats);
    let states = gio::Menu::new();
    for (target, key, english, _) in STATES {
        states.append(
            Some(&tr(key, english)),
            Some(&format!("win.filter-state::{target}")),
        );
    }
    menu.append_section(
        Some(&tr("library.filter.readState", "Read or unread")),
        &states,
    );
    if !folders.is_empty() {
        let section = gio::Menu::new();
        let any = gio::MenuItem::new(Some(&tr("library.scope.all", "Everywhere")), None);
        any.set_action_and_target_value(Some("win.filter-folder"), Some(&ANY_FOLDER.to_variant()));
        section.append_item(&any);
        for folder in folders {
            let item = gio::MenuItem::new(Some(folder), None);
            item.set_action_and_target_value(Some("win.filter-folder"), Some(&folder.to_variant()));
            section.append_item(&item);
        }
        menu.append_section(
            Some(&tr("library.filter.library", "Which library")),
            &section,
        );
    }
    let clear = gio::Menu::new();
    clear.append(
        Some(&tr("library.filter.clear", "Clear filters")),
        Some("win.clear-filters"),
    );
    menu.append_section(None, &clear);
    menu
}

pub fn sort_menu() -> gio::Menu {
    let menu = gio::Menu::new();
    for (target, key, english, _) in SORTS {
        menu.append(
            Some(&tr(key, english)),
            Some(&format!("win.sort::{target}")),
        );
    }
    menu
}

/// How a filter or sort choice changes the header bar's state.
type Change = fn(&mut QueryState, &str);

/// The stateful actions behind the filter and sort menus. `changed` runs after each.
pub fn install(window: &adw::ApplicationWindow, shared: &Shared, changed: fn(&Shared)) {
    let choices: [(&str, &str, Change); 4] = [
        ("filter-format", "any", |state, target| {
            state.filters.format = FORMATS
                .iter()
                .find(|(name, _)| *name == target)
                .and_then(|(_, format)| *format);
        }),
        ("filter-state", "any", |state, target| {
            state.filters.read_state = STATES
                .iter()
                .find(|(name, ..)| *name == target)
                .and_then(|(.., read)| *read);
        }),
        ("filter-folder", ANY_FOLDER, |state, target| {
            state.filters.source = (!target.is_empty()).then(|| target.to_owned());
        }),
        ("sort", "title", |state, target| {
            state.sort = SORTS
                .iter()
                .find(|(name, ..)| *name == target)
                .map_or(Sort::Title, |(.., sort)| *sort);
        }),
    ];
    for (name, initial, change) in choices {
        let action = gio::SimpleAction::new_stateful(
            name,
            Some(glib::VariantTy::STRING),
            &initial.to_variant(),
        );
        let on = shared.clone();
        action.connect_activate(move |action, target| {
            let Some(target) = target.and_then(|target| target.get::<String>()) else {
                return;
            };
            action.set_state(&target.to_variant());
            if let Some(ui) = on.library_ui.borrow().clone() {
                change(&mut ui.state.borrow_mut(), &target);
            }
            changed(&on);
        });
        window.add_action(&action);
    }
    let clear = gio::SimpleAction::new("clear-filters", None);
    let on = shared.clone();
    let weak = window.downgrade();
    clear.connect_activate(move |_, _| {
        if let Some(ui) = on.library_ui.borrow().clone() {
            ui.state.borrow_mut().filters = Default::default();
        }
        if let Some(window) = weak.upgrade() {
            reflect(&window, &QueryState::default());
        }
        changed(&on);
    });
    window.add_action(&clear);
}

/// Sets the menus' radio marks to what the state holds, after a change made elsewhere
/// (a folder chosen in the sidebar, or every filter cleared).
pub fn reflect(window: &adw::ApplicationWindow, state: &QueryState) {
    let set = |name: &str, target: &str| {
        if let Some(action) = window
            .lookup_action(name)
            .and_downcast::<gio::SimpleAction>()
        {
            action.set_state(&target.to_variant());
        }
    };
    let format = FORMATS
        .iter()
        .find(|(_, format)| *format == state.filters.format)
        .map_or("any", |(name, _)| *name);
    set("filter-format", format);
    let read = STATES
        .iter()
        .find(|(.., read)| *read == state.filters.read_state)
        .map_or("any", |(name, ..)| *name);
    set("filter-state", read);
    set(
        "filter-folder",
        state.filters.source.as_deref().unwrap_or(ANY_FOLDER),
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::query::{Destination, Filters};

    #[test]
    fn the_sort_button_reads_as_an_ordering_and_the_filter_button_counts() {
        assert_eq!(sort_label(Sort::Title), "Sort: Title");
        assert_eq!(sort_label(Sort::LastRead), "Sort: Last read");
        let mut state = QueryState::at(Destination::Library);
        assert_eq!(filter_label(&state), "Filter");
        state.filters = Filters {
            source: Some("Comics".into()),
            read_state: Some(ReadState::Unread),
            ..Filters::default()
        };
        assert_eq!(filter_label(&state), "Filter · 2");
        assert_eq!(filter_description(&state), "2 filters active");
    }
}
