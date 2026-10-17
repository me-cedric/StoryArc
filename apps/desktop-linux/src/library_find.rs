//! The search field's behaviour in the library window: entering it opens the search
//! page, typing narrows, Enter and leaving remember the query, the recent searches put a
//! query back, and the scope is kept. The page itself is `library_search.rs`.

use std::rc::Rc;

use adw::prelude::*;

use crate::app::Shared;
use crate::library_search;
use crate::library_window::{LibraryUi, refresh};
use crate::session;

pub(crate) fn connect_search(shared: &Shared, ui: &Rc<LibraryUi>) {
    let on = shared.clone();
    ui.search.connect_search_changed(move |entry| {
        if let Some(ui) = on.library_ui.borrow().clone() {
            let mut state = ui.state.borrow_mut();
            state.typed(&entry.text());
            if !entry.text().is_empty() {
                state.entered_search();
            }
        }
        refresh(&on);
    });
    let focus = gtk::EventControllerFocus::new();
    let on = shared.clone();
    focus.connect_enter(move |_| {
        if let Some(ui) = on.library_ui.borrow().clone() {
            ui.state.borrow_mut().entered_search();
        }
        refresh(&on);
    });
    ui.search.add_controller(focus);
    let on = shared.clone();
    ui.search.connect_activate(move |entry| {
        if let Some(ui) = on.library_ui.borrow().clone() {
            remember(&ui, &entry.text());
        }
    });
    let on = shared.clone();
    ui.search.connect_stop_search(move |_| {
        if let Some(ui) = on.library_ui.borrow().clone() {
            leave_search(&on, &ui);
        }
        refresh(&on);
    });
    let on = shared.clone();
    ui.search_ui.on_recent(move |query| {
        if let Some(ui) = on.library_ui.borrow().clone() {
            ui.search.set_text(&query);
            ui.search.set_position(-1);
        }
    });
    let on = shared.clone();
    ui.search_ui
        .on_suggested(move |publication| crate::library_data::show_detail(&on, publication));
    let on = shared.clone();
    ui.search_ui.clear.connect_clicked(move |_| {
        if let Some(ui) = on.library_ui.borrow().clone() {
            ui.memory.borrow_mut().clear();
            session::save_search(&ui.memory.borrow());
        }
        refresh(&on);
    });
    let on = shared.clone();
    ui.search_ui.scope.connect_selected_notify(move |dropdown| {
        set_scope(&on, library_search::scope_at(dropdown.selected()));
    });
    ui.search_ui
        .scope
        .set_selected(library_search::position_of(ui.memory.borrow().scope));
    let on = shared.clone();
    ui.search_ui.widen.connect_clicked(move |_| {
        set_scope(&on, crate::library::search::Scope::Everywhere);
    });
}

pub(crate) fn set_scope(shared: &Shared, scope: crate::library::search::Scope) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    ui.memory.borrow_mut().scope = scope;
    ui.state.borrow_mut().scope = scope;
    session::save_search(&ui.memory.borrow());
    let position = library_search::position_of(scope);
    if ui.search_ui.scope.selected() != position {
        ui.search_ui.scope.set_selected(position);
    }
    refresh(shared);
}

pub(crate) fn remember(ui: &LibraryUi, query: &str) {
    ui.memory.borrow_mut().remember(query);
    session::save_search(&ui.memory.borrow());
}

/// Leaves search: the query is offered again as a recent search, and the column returns
/// to the destination the reader was on (`navigation-shell`, Leaving search).
pub(crate) fn leave_search(_shared: &Shared, ui: &LibraryUi) {
    let text = ui.state.borrow().text.clone();
    remember(ui, &text);
    ui.state.borrow_mut().left_search();
    if !ui.search.text().is_empty() {
        ui.search.set_text("");
    }
}
