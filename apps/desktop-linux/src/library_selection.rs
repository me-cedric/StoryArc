//! The library's header bar and its selection mode (`native-experience`, Chrome for a
//! mode a reader is in). The browsing header holds the search field, the Select button
//! and the View, Filter and Sort menus; the selection header replaces it while a reader
//! is choosing covers, and the mode's actions sit in a bar at the foot.

use std::rc::Rc;

use adw::prelude::*;
use gtk::glib;
use storyarc_core::domain::Timestamp;

use crate::app::Shared;
use crate::library_cells;
use crate::library_menus;
use crate::library_views::{self, Item};
use crate::library_window::{LibraryUi, add};
use crate::session;
use crate::strings::tr;

/// The content column's header bar and the selection mode's: the one replaces the other
/// rather than stacking on it, and the mode's actions sit in a bar at the foot.
pub(crate) struct ContentBars {
    pub(crate) header: gtk::Stack,
    pub(crate) stack: gtk::Stack,
    pub(crate) selection_title: adw::WindowTitle,
    pub(crate) selection_bar: gtk::ActionBar,
    pub(crate) mark_read: gtk::Button,
    pub(crate) filter: gtk::MenuButton,
    pub(crate) sort: gtk::MenuButton,
}

impl ContentBars {
    pub(crate) fn new(search: &gtk::SearchEntry) -> Self {
        let header = adw::HeaderBar::new();
        header.set_title_widget(Some(search));
        let view = gtk::MenuButton::builder()
            .icon_name("view-grid-symbolic")
            .tooltip_text(tr("library.view", "View"))
            .menu_model(&library_menus::view_menu())
            .build();
        view.update_property(&[gtk::accessible::Property::Label(&tr(
            "library.view",
            "View",
        ))]);
        let filter = gtk::MenuButton::builder()
            .label(tr("library.filter", "Filter"))
            .menu_model(&library_menus::filter_menu(&[]))
            .build();
        let sort = gtk::MenuButton::builder()
            .label(library_menus::sort_label(Default::default()))
            .menu_model(&library_menus::sort_menu())
            .build();
        let select = gtk::Button::builder()
            .icon_name("selection-mode-symbolic")
            .tooltip_text(tr("library.select", "Select"))
            .action_name("win.select-mode")
            .build();
        select.update_property(&[gtk::accessible::Property::Label(&tr(
            "library.select",
            "Select",
        ))]);
        header.pack_end(&view);
        header.pack_end(&sort);
        header.pack_end(&filter);
        header.pack_start(&select);

        let selection_title = adw::WindowTitle::new(&library_cells::selected_title(0), "");
        let done = gtk::Button::builder()
            .label(tr("library.select.done", "Done"))
            .action_name("win.leave-selection")
            .build();
        let selecting = adw::HeaderBar::builder()
            .title_widget(&selection_title)
            .css_classes(["selection-mode"])
            .build();
        selecting.pack_end(&done);
        let stack = gtk::Stack::builder()
            .transition_type(gtk::StackTransitionType::Crossfade)
            .build();
        stack.add_named(&header, Some("browse"));
        stack.add_named(&selecting, Some("select"));

        let mark_read = gtk::Button::builder()
            .label(tr("library.mark.read", "Mark as read"))
            .action_name("win.mark-read")
            .build();
        let selection_bar = gtk::ActionBar::builder().revealed(false).build();
        selection_bar.pack_start(&mark_read);
        Self {
            header: stack.clone(),
            stack,
            selection_title,
            selection_bar,
            mark_read,
            filter,
            sort,
        }
    }
}
/// Selection mode (`native-experience`, Chrome for a mode a reader is in): GNOME's own
/// form, as Files and Photos draw it. The header bar is replaced by one that states how
/// many are chosen and holds Done, the one way out, never disabled; the actions sit in a
/// bar at the foot, present and drawn inert until something is chosen, each named.
pub(crate) fn install_selection_actions(shared: &Shared, ui: &Rc<LibraryUi>) {
    let on = shared.clone();
    add(&ui.window, "select-mode", move |_| set_selecting(&on, true));
    let on = shared.clone();
    add(&ui.window, "leave-selection", move |_| {
        set_selecting(&on, false)
    });
    let weak = Rc::downgrade(ui);
    add(&ui.window, "select-all", move |_| {
        if let Some(ui) = weak.upgrade() {
            ui.selection.select_all();
        }
    });
    let on = shared.clone();
    add(&ui.window, "mark-read", move |_| mark_selected_read(&on));
    let weak = Rc::downgrade(ui);
    ui.selection
        .connect_selection_changed(move |selection, _, _| {
            if let Some(ui) = weak.upgrade() {
                let count = usize::try_from(selection.selection().size()).unwrap_or(0);
                // Choosing anything, by Control or Shift click or Select All, is selection
                // mode: the bar says how many and holds the way out.
                if count > 0 && !ui.selecting.get() {
                    reveal(&ui, true);
                }
                ui.selection_title
                    .set_title(&library_cells::selected_title(count));
                ui.mark_read.set_sensitive(count > 0);
            }
        });
    let escape = gtk::ShortcutController::new();
    let on = shared.clone();
    escape.add_shortcut(gtk::Shortcut::new(
        gtk::ShortcutTrigger::parse_string("Escape"),
        Some(gtk::CallbackAction::new(move |_, _| {
            let selecting = on
                .library_ui
                .borrow()
                .as_ref()
                .is_some_and(|ui| ui.selecting.get());
            if selecting {
                set_selecting(&on, false);
                glib::Propagation::Stop
            } else {
                glib::Propagation::Proceed
            }
        })),
    ));
    ui.window.add_controller(escape);
}

/// Swaps the header and the action bar for selection mode's, or back; the choice itself
/// is left as it is.
fn reveal(ui: &LibraryUi, on: bool) {
    ui.selecting.set(on);
    ui.header
        .set_visible_child_name(if on { "select" } else { "browse" });
    ui.selection_bar.set_revealed(on);
}

pub(crate) fn set_selecting(shared: &Shared, on: bool) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    reveal(&ui, on);
    ui.selection.unselect_all();
    ui.mark_read.set_sensitive(false);
    ui.selection_title
        .set_title(&library_cells::selected_title(0));
}

/// Marks every chosen publication finished; a series cell marks each of its issues.
pub(crate) fn mark_selected_read(shared: &Shared) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    let chosen = ui.selection.selection();
    let store = shared.progress_store();
    let now = Timestamp::now();
    for index in 0..u32::try_from(chosen.size()).unwrap_or(0) {
        let position = chosen.nth(index);
        let Some(item) = library_views::item_at(&ui.selection, position) else {
            continue;
        };
        let item = item.borrow::<Item>();
        let publications = item.publication.iter().chain(item.issues.iter());
        for publication in publications {
            let pages = i64::try_from(publication.page_count.unwrap_or(1)).unwrap_or(1);
            let record = storyarc_core::domain::ReadingProgress::new(
                publication.identity.clone(),
                storyarc_core::domain::ReadingPosition::page((pages - 1).max(0), pages.max(1)),
                now,
            )
            .finished(true, now);
            if let Err(error) = store.write(&record) {
                glib::g_warning!(session::LOG_DOMAIN, "Could not mark as read: {error}");
            }
        }
    }
    set_selecting(shared, false);
    shared.library_changed();
}
