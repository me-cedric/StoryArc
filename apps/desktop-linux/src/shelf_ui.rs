//! Collections and reading lists in the library window (task 3.19a, as 3.15a;
//! `collections-and-reading-lists`): the Shelves section of the sidebar, the shelf page,
//! Add to Shelf in the cell's menu and on the selection bar, Remove from Shelf as the bulk
//! action on a shelf page, and the pinned shelves on Home. The rules are `shelf_rules.rs`;
//! the shelves live in the library document this device keeps (`session.rs`), so a sync
//! carries them.

use std::rc::Rc;

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::domain::{Publication, Timestamp};
use storyarc_core::portability::LibrarySnapshot;

use crate::app::Shared;
use crate::library_views::{self, CellHooks, Item};
use crate::shelf_rules::{self, ShelfRef, SidebarShelf};
use crate::strings::{tr, tr_args, tr_plural};
use crate::{library_cells, library_data, library_window, session};

/// Replaces the library document with what `change` makes of it, writes it and redraws.
fn mutate(shared: &Shared, change: impl FnOnce(&LibrarySnapshot) -> LibrarySnapshot) {
    let next = change(&shared.document.borrow());
    session::save_library_snapshot(&next);
    *shared.document.borrow_mut() = next;
    shared.library_changed();
}

pub fn rows(shared: &Shared) -> Vec<SidebarShelf> {
    let document = shared.document.borrow();
    shelf_rules::sidebar(&document.shelves, &document.pinned_shelves)
}

fn name_of(shared: &Shared, shelf: &ShelfRef) -> String {
    rows(shared)
        .into_iter()
        .find(|row| &row.shelf == shelf)
        .map_or_else(String::new, |row| row.name)
}

/// The Shelves section: one row each, pinned first, then New Shelf.
pub fn fill_sidebar(shared: &Shared, list: &gtk::ListBox) {
    list.remove_all();
    for row in rows(shared) {
        let line = gtk::Box::builder().spacing(6).build();
        if row.pinned {
            line.append(&gtk::Image::from_icon_name("view-pin-symbolic"));
        }
        line.append(
            &gtk::Label::builder()
                .label(&row.name)
                .xalign(0.0)
                .hexpand(true)
                .ellipsize(gtk::pango::EllipsizeMode::End)
                .build(),
        );
        line.append(
            &gtk::Label::builder()
                .label(row.count.to_string())
                .css_classes(["dimmed", "caption"])
                .build(),
        );
        list.append(&line);
    }
    for (key, english) in [
        ("shelves.new", "New Shelf…"),
        ("shelves.newList", "New Reading List…"),
    ] {
        list.append(
            &gtk::Label::builder()
                .label(tr(key, english))
                .xalign(0.0)
                .css_classes(["dimmed"])
                .build(),
        );
    }
}

/// A row of the section was chosen: a shelf opens on its page, the last row makes one.
pub fn activate_row(shared: &Shared, index: usize) {
    let shelves = rows(shared);
    match shelves.get(index) {
        Some(row) => open_shelf(shared, &row.shelf),
        None => new_shelf_dialog(shared, Vec::new(), index > shelves.len()),
    }
}

fn open_shelf(shared: &Shared, shelf: &ShelfRef) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    *shared.open_shelf.borrow_mut() = Some(shelf.clone());
    ui.navigation.pop_to_tag("content");
    let page = shelf_page(shared, shelf);
    ui.navigation.push(&page);
    ui.split.set_show_content(true);
}

/// Asks for a name and makes a collection; the publications given join it at once.
pub fn new_shelf_dialog(shared: &Shared, then_add: Vec<Publication>, reading_list: bool) {
    let entry = gtk::Entry::builder()
        .placeholder_text(tr("shelves.name", "Name"))
        .activates_default(true)
        .build();
    let title = if reading_list {
        tr("shelves.newList", "New Reading List…")
    } else {
        tr("shelves.new", "New Shelf…")
    };
    let alert = adw::AlertDialog::new(Some(&title), None);
    alert.set_extra_child(Some(&entry));
    alert.add_responses(&[
        ("cancel", &tr("sources.rename.cancel", "Cancel")),
        ("create", &tr("shelves.create", "Create")),
    ]);
    alert.set_response_appearance("create", adw::ResponseAppearance::Suggested);
    alert.set_default_response(Some("create"));
    alert.set_close_response("cancel");
    let on = shared.clone();
    let field = entry.clone();
    alert.connect_response(None, move |_, response| {
        if response != "create" {
            return;
        }
        let name = field.text().to_string();
        let (made, shelf) = if reading_list {
            shelf_rules::create_list(&on.document.borrow().shelves, &name)
        } else {
            shelf_rules::create_collection(&on.document.borrow().shelves, &name)
        };
        let Some(shelf) = shelf else { return };
        mutate(&on, |document| {
            let mut next = document.clone();
            next.shelves = made.clone();
            if then_add.is_empty() {
                return shelf_rules::touched(&next, &shelf, Timestamp::now());
            }
            next.shelves = shelf_rules::add_to(&next.shelves, &shelf, &then_add);
            shelf_rules::touched(&next, &shelf, Timestamp::now())
        });
        if !then_add.is_empty() {
            on.toast(&tr_args("shelves.added %s", "Added to %s", &[&name.trim()]));
        }
    });
    let parent = shared.library.borrow().clone();
    alert.present(parent.as_ref());
}

/// Adds publications to a shelf, stamping it, and says so in a toast.
pub fn add_to(shared: &Shared, shelf: &ShelfRef, publications: &[Publication]) {
    if publications.is_empty() {
        return;
    }
    mutate(shared, |document| {
        let mut next = document.clone();
        next.shelves = shelf_rules::add_to(&document.shelves, shelf, publications);
        shelf_rules::touched(&next, shelf, Timestamp::now())
    });
    shared.toast(&tr_args(
        "shelves.added %s",
        "Added to %s",
        &[&name_of(shared, shelf)],
    ));
}

fn remove_from(shared: &Shared, shelf: &ShelfRef, publications: &[Publication]) {
    mutate(shared, |document| {
        let mut next = document.clone();
        next.shelves = shelf_rules::remove_from(&document.shelves, shelf, publications);
        shelf_rules::touched(&next, shelf, Timestamp::now())
    });
}

fn delete_shelf(shared: &Shared, shelf: &ShelfRef) {
    mutate(shared, |document| {
        shelf_rules::deleted(document, shelf, Timestamp::now(), session::DEVICE)
    });
}

fn toggle_pin(shared: &Shared, shelf: &ShelfRef) {
    mutate(shared, |document| LibrarySnapshot {
        pinned_shelves: shelf_rules::toggle_pin(&document.pinned_shelves, shelf),
        ..document.clone()
    });
}

fn token(shelf: &ShelfRef) -> String {
    match shelf {
        ShelfRef::Collection(id) => format!("c:{id}"),
        ShelfRef::List(id) => format!("l:{id}"),
    }
}

fn of_token(text: &str) -> Option<ShelfRef> {
    let (kind, id) = text.split_once(':')?;
    match kind {
        "c" => Some(ShelfRef::Collection(id.to_owned())),
        "l" => Some(ShelfRef::List(id.to_owned())),
        _ => None,
    }
}

/// The publications the selection stands for: a series cell stands for each issue.
pub fn selected(shared: &Shared) -> Vec<Publication> {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return Vec::new();
    };
    let chosen = ui.selection.selection();
    let mut found = Vec::new();
    for index in 0..u32::try_from(chosen.size()).unwrap_or(0) {
        let Some(item) = library_views::item_at(&ui.selection, chosen.nth(index)) else {
            continue;
        };
        let item = item.borrow::<Item>();
        found.extend(item.publication.iter().chain(item.issues.iter()).cloned());
    }
    found
}

/// The Add to Shelf menu: every shelf, then a new one.
fn add_menu(shared: &Shared) -> gio::Menu {
    let menu = gio::Menu::new();
    for row in rows(shared) {
        let item = gio::MenuItem::new(Some(&row.name), None);
        item.set_action_and_target_value(
            Some("win.add-to-shelf"),
            Some(&token(&row.shelf).to_variant()),
        );
        menu.append_item(&item);
    }
    menu.append(
        Some(&tr("shelves.new", "New Shelf…")),
        Some("win.new-shelf"),
    );
    menu
}

/// The selection bar's Add to Shelf button, and the actions behind it.
pub fn install(shared: &Shared, ui: &Rc<library_window::LibraryUi>) {
    let button = gtk::MenuButton::builder()
        .label(tr("shelves.add", "Add to Shelf"))
        .build();
    let on = Rc::downgrade(shared);
    button.set_create_popup_func(move |button| {
        if let Some(shared) = on.upgrade() {
            button.set_menu_model(Some(&add_menu(&shared)));
        }
    });
    ui.selection_bar.pack_start(&button);
    let action = gio::SimpleAction::new("add-to-shelf", Some(glib::VariantTy::STRING));
    let on = shared.clone();
    action.connect_activate(move |_, target| {
        let Some(shelf) = target
            .and_then(|t| t.get::<String>())
            .as_deref()
            .and_then(of_token)
        else {
            return;
        };
        add_to(&on, &shelf, &selected(&on));
    });
    ui.window.add_action(&action);
    let new = gio::SimpleAction::new("new-shelf", None);
    let on = shared.clone();
    new.connect_activate(move |_, _| new_shelf_dialog(&on, selected(&on), false));
    ui.window.add_action(&new);
}

/// Add to Shelf in a cover's menu: a submenu of the shelves, acting on that publication.
pub fn extend_cell_menu(
    shared: &Shared,
    menu: &gio::Menu,
    group: &gio::SimpleActionGroup,
    publication: &Publication,
) {
    let sub = gio::Menu::new();
    for (index, row) in rows(shared).into_iter().enumerate() {
        let name = format!("shelf-{index}");
        sub.append(Some(&row.name), Some(&format!("cell.{name}")));
        let action = gio::SimpleAction::new(&name, None);
        let on = shared.clone();
        let publication = publication.clone();
        action.connect_activate(move |_, _| {
            add_to(&on, &row.shelf, std::slice::from_ref(&publication))
        });
        group.add_action(&action);
    }
    sub.append(
        Some(&tr("shelves.new", "New Shelf…")),
        Some("cell.shelf-new"),
    );
    let action = gio::SimpleAction::new("shelf-new", None);
    let on = shared.clone();
    let publication = publication.clone();
    action.connect_activate(move |_, _| new_shelf_dialog(&on, vec![publication.clone()], false));
    group.add_action(&action);
    menu.append_submenu(Some(&tr("shelves.add", "Add to Shelf")), &sub);
}

/// A shelf's page: its publications, with Remove from Shelf as the bulk action and a menu
/// that pins it to Home or deletes it.
pub fn shelf_page(shared: &Shared, shelf: &ShelfRef) -> adw::NavigationPage {
    let store = gio::ListStore::new::<glib::BoxedAnyObject>();
    let selection = gtk::MultiSelection::new(Some(store.clone()));
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return adw::NavigationPage::new(&gtk::Label::new(None), "");
    };
    let hooks = CellHooks {
        model: selection.clone(),
        covers: ui.covers.clone(),
        menu: library_cells::cell_menu(shared, || 1),
        selecting: Rc::default(),
    };
    let grid = library_views::grid_view(&hooks, ui.tier());
    let on = shared.clone();
    grid.connect_activate(move |grid, position| {
        library_window::activate_item(&on, grid.model(), position);
    });
    let note = gtk::Label::builder()
        .xalign(0.0)
        .margin_start(18)
        .margin_top(6)
        .css_classes(["dimmed"])
        .visible(false)
        .build();
    let fill = {
        let (shared, shelf, store, note) =
            (shared.clone(), shelf.clone(), store.clone(), note.clone());
        move || {
            let library = shared.sources.publications();
            let document = shared.document.borrow();
            let Some(page) = shelf_rules::page(&document.shelves, &shelf, &library) else {
                store.remove_all();
                return;
            };
            let items: Vec<glib::BoxedAnyObject> = page
                .publications
                .iter()
                .map(|p| library_views::boxed(library_data::item_for(&shared, p)))
                .collect();
            store.splice(0, store.n_items(), &items);
            note.set_visible(page.unavailable > 0);
            note.set_label(&tr_plural(
                "shelves.unavailable %d",
                "%d title is not on this device right now",
                "%d titles are not on this device right now",
                page.unavailable as u64,
            ));
        }
    };
    fill();

    let menu = gio::Menu::new();
    menu.append(Some(&tr("shelves.pin", "Pin to Home")), Some("shelf.pin"));
    menu.append(
        Some(&tr("shelves.delete", "Delete Shelf…")),
        Some("shelf.delete"),
    );
    let actions = gio::SimpleActionGroup::new();
    let pin = gio::SimpleAction::new("pin", None);
    let (on, which) = (shared.clone(), shelf.clone());
    pin.connect_activate(move |_, _| toggle_pin(&on, &which));
    actions.add_action(&pin);
    let delete = gio::SimpleAction::new("delete", None);
    let (on, which) = (shared.clone(), shelf.clone());
    delete.connect_activate(move |_, _| confirm_delete(&on, &which));
    actions.add_action(&delete);
    let more = gtk::MenuButton::builder()
        .icon_name("view-more-symbolic")
        .menu_model(&menu)
        .tooltip_text(tr("shelves.options", "Shelf options"))
        .build();
    more.update_property(&[gtk::accessible::Property::Label(&tr(
        "shelves.options",
        "Shelf options",
    ))]);
    more.insert_action_group("shelf", Some(&actions));
    let header = adw::HeaderBar::new();
    header.pack_end(&more);

    let remove = gtk::Button::builder()
        .label(tr("shelves.remove", "Remove from Shelf"))
        .sensitive(false)
        .build();
    let bar = gtk::ActionBar::new();
    bar.pack_start(&remove);
    let button = remove.clone();
    selection.connect_selection_changed(move |selection, _, _| {
        button.set_sensitive(selection.selection().size() > 0);
    });
    let (on, which, chosen) = (shared.clone(), shelf.clone(), selection.clone());
    remove.connect_clicked(move |_| {
        let bits = chosen.selection();
        let publications: Vec<Publication> = (0..u32::try_from(bits.size()).unwrap_or(0))
            .filter_map(|i| library_views::item_at(&chosen, bits.nth(i)))
            .filter_map(|item| item.borrow::<Item>().publication.clone())
            .collect();
        remove_from(&on, &which, &publications);
    });

    let column = gtk::Box::new(gtk::Orientation::Vertical, 0);
    column.append(&note);
    column.append(
        &gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .vexpand(true)
            .child(&grid)
            .build(),
    );
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);
    toolbar.add_bottom_bar(&bar);
    toolbar.set_content(Some(&column));
    let page = adw::NavigationPage::builder()
        .title(name_of(shared, shelf))
        .tag("shelf")
        .child(&toolbar)
        .build();
    // The page follows the document: a removal redraws it in place.
    let weak = page.downgrade();
    *shared.shelf_fill.borrow_mut() = Some(Box::new(move || {
        if weak.upgrade().is_some() {
            fill();
        }
    }));
    page
}

fn confirm_delete(shared: &Shared, shelf: &ShelfRef) {
    let name = name_of(shared, shelf);
    let alert = adw::AlertDialog::new(
        Some(&tr_args("shelves.delete.title %s", "Delete %s?", &[&name])),
        Some(&tr(
            "shelves.delete.body",
            "The shelf goes. The titles on it stay in your library, and so do your reading positions.",
        )),
    );
    alert.add_responses(&[
        ("cancel", &tr("sources.rename.cancel", "Cancel")),
        ("delete", &tr("shelves.delete.confirm", "Delete")),
    ]);
    alert.set_response_appearance("delete", adw::ResponseAppearance::Destructive);
    alert.set_close_response("cancel");
    let (on, which) = (shared.clone(), shelf.clone());
    alert.connect_response(None, move |_, response| {
        if response == "delete" {
            delete_shelf(&on, &which);
            if let Some(ui) = on.library_ui.borrow().clone() {
                ui.navigation.pop_to_tag("content");
            }
        }
    });
    let parent = shared.library.borrow().clone();
    alert.present(parent.as_ref());
}

/// What Home draws for the pinned shelves.
pub fn home_rows(shared: &Shared) -> Vec<shelf_rules::HomeShelf> {
    let document = shared.document.borrow();
    shelf_rules::home(
        &document.shelves,
        &document.pinned_shelves,
        &shared.sources.publications(),
    )
}

/// A pinned shelf's heading on Home leads to its page.
pub fn show(shared: &Shared, shelf: &ShelfRef) {
    open_shelf(shared, shelf);
}
