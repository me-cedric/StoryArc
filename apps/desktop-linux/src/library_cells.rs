//! What the library window does with its cells: the menu on a cover and starting over,
//! a series opened on a page of its own, the index down the trailing edge, and the
//! selection mode's bar. The rules are `library/context.rs` and `library/shelf.rs`.

use std::rc::Rc;

use adw::prelude::*;
use gtk::{gdk, gio, glib};
use storyarc_core::domain::Publication;

use crate::app::Shared;
use crate::folders::Access;
use crate::library::context::{self, CellAction};
use crate::library::shelf::IndexEntry;
use crate::library_views::{self, CellMenu, Item};
use crate::session::LOG_DOMAIN;
use crate::strings::{tr, tr_args, tr_plural};
use crate::{library_data, library_window};

/// The menu a right click opens on a cover. `selected` says how many covers are chosen.
pub fn cell_menu(shared: &Shared, selected: impl Fn() -> usize + 'static) -> CellMenu {
    let weak = Rc::downgrade(shared);
    Rc::new(move |widget, boxed, x, y| {
        let Some(shared) = weak.upgrade() else {
            return;
        };
        let item = boxed.borrow::<Item>();
        let Some(publication) = item.publication.clone() else {
            return;
        };
        let readable = shared
            .sources
            .source_of(&publication)
            .is_none_or(|(_, access)| access == Access::Readable);
        let summary = library_data::summary_of(&shared, &publication);
        let actions = context::cell_actions(summary, readable, selected());
        let menu = gio::Menu::new();
        let group = gio::SimpleActionGroup::new();
        for action in actions {
            let (key, english) = action.label();
            menu.append(
                Some(&tr(key, english)),
                Some(&format!("cell.{}", action.name())),
            );
            let simple = gio::SimpleAction::new(action.name(), None);
            let on = shared.clone();
            let target = publication.clone();
            let parent = widget.clone();
            simple.connect_activate(move |_, _| run(&on, action, &target, &parent));
            group.add_action(&simple);
        }
        crate::shelf_ui::extend_cell_menu(&shared, &menu, &group, &publication);
        widget.insert_action_group("cell", Some(&group));
        let popover = gtk::PopoverMenu::from_model(Some(&menu));
        popover.set_parent(widget);
        popover.set_has_arrow(false);
        popover.set_pointing_to(Some(&gdk::Rectangle::new(x as i32, y as i32, 1, 1)));
        popover.connect_closed(|popover| {
            let popover = popover.clone();
            glib::idle_add_local_once(move || popover.unparent());
        });
        popover.popup();
    })
}

fn run(shared: &Shared, action: CellAction, publication: &Publication, parent: &gtk::Widget) {
    match action {
        CellAction::Read => library_data::read(shared)(publication),
        CellAction::ShowDetails => library_data::show_detail(shared, publication),
        CellAction::StartOver => confirm_start_over(shared, publication, parent),
        CellAction::ShowInFiles => {
            if let Some(path) = publication.identity.normalized_path.as_deref() {
                gtk::FileLauncher::new(Some(&gio::File::for_path(path))).open_containing_folder(
                    gtk::Window::NONE,
                    None::<&gio::Cancellable>,
                    |_| {},
                );
            }
        }
    }
}

/// Start from the beginning, after a confirmation that says what it forgets and what it
/// leaves (`reading-progress`, Restart deliberately).
fn confirm_start_over(shared: &Shared, publication: &Publication, parent: &gtk::Widget) {
    let dialog = adw::AlertDialog::new(
        Some(&tr_args(
            "library.restart.title %s",
            "Start “%s” from the beginning?",
            &[&publication.display_title],
        )),
        Some(&tr(
            "library.restart.body",
            "Your place here is forgotten, and it opens at page one next time. Nothing else changes, and the file itself is untouched.",
        )),
    );
    dialog.add_responses(&[
        ("cancel", &tr("sources.rename.cancel", "Cancel")),
        (
            "restart",
            &tr("library.restart.confirm", "Start from the beginning"),
        ),
    ]);
    dialog.set_response_appearance("restart", adw::ResponseAppearance::Destructive);
    dialog.set_close_response("cancel");
    dialog.set_default_response(Some("cancel"));
    let on = shared.clone();
    let identity = publication.identity.clone();
    dialog.connect_response(None, move |_, response| {
        if response != "restart" {
            return;
        }
        if let Err(error) = on.progress_store().store().forget_progress(&identity) {
            glib::g_warning!(LOG_DOMAIN, "Could not forget a reading position: {error}");
        }
        on.library_changed();
    });
    dialog.present(Some(parent));
}

/// A series opened: its issues in their own order, each carrying the marks a cover
/// carries in the grid, on a page pushed over the library; Back returns to the shelf
/// where the reader left it (`library-browsing`, Opening a series).
pub fn series_page(shared: &Shared, name: &str, issues: &[Publication]) -> adw::NavigationPage {
    let store = gio::ListStore::new::<glib::BoxedAnyObject>();
    let items: Vec<glib::BoxedAnyObject> = issues
        .iter()
        .map(|publication| library_views::boxed(library_data::item_for(shared, publication)))
        .collect();
    store.splice(0, 0, &items);
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return adw::NavigationPage::new(&gtk::Label::new(None), name);
    };
    let selection = gtk::MultiSelection::new(Some(store));
    let hooks = library_views::CellHooks {
        model: selection.clone(),
        covers: ui.covers.clone(),
        menu: cell_menu(shared, || 1),
        selecting: Rc::default(),
    };
    let grid = library_views::grid_view(&hooks, ui.tier());
    let on = shared.clone();
    grid.connect_activate(move |grid, position| {
        library_window::activate_item(&on, grid.model(), position);
    });
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&adw::HeaderBar::new());
    toolbar.set_content(Some(
        &gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .vexpand(true)
            .child(&grid)
            .build(),
    ));
    adw::NavigationPage::builder()
        .title(name)
        .tag("series")
        .child(&toolbar)
        .build()
}

/// The index down the trailing edge: one named group of letters, each moving the shelf
/// to the first row filed under it and saying where it moved. Empty for an order no
/// letter describes, so nothing is drawn (`library-browsing`, An index down the side).
pub fn fill_index(rail: &gtk::Box, entries: &[IndexEntry], jump: Rc<dyn Fn(u32)>) {
    while let Some(child) = rail.first_child() {
        rail.remove(&child);
    }
    rail.set_visible(entries.len() > 1);
    for entry in entries {
        let button = gtk::Button::builder()
            .label(&entry.letter)
            .css_classes(["flat", "caption"])
            .tooltip_text(tr_args(
                "library.index.jump %s",
                "Jump to %s",
                &[&entry.letter],
            ))
            .build();
        let jump = jump.clone();
        let position = entry.position;
        let letter = entry.letter.clone();
        button.connect_clicked(move |button| {
            jump(position);
            button.announce(
                &tr_args("library.index.jump %s", "Jump to %s", &[&letter]),
                gtk::AccessibleAnnouncementPriority::Medium,
            );
        });
        rail.append(&button);
    }
}

pub fn index_rail() -> gtk::Box {
    let rail = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .halign(gtk::Align::End)
        .valign(gtk::Align::Center)
        .margin_end(6)
        .css_classes(["card"])
        .accessible_role(gtk::AccessibleRole::Group)
        .visible(false)
        .build();
    rail.update_property(&[gtk::accessible::Property::Label(&tr(
        "library.index",
        "Alphabetical index",
    ))]);
    rail
}

/// What the header says while selecting: how many are chosen, in the catalogue's plural.
pub fn selected_title(count: usize) -> String {
    tr_plural(
        "library.selected %d",
        "%d selected",
        "%d selected",
        count as u64,
    )
}
