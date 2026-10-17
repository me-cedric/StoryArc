//! The search page (task 2.35b; `library-browsing`, Search; `navigation-shell`, Reaching
//! search). The field stays in the header bar. Entering it opens the page before a word
//! is typed: recent searches to offer again, or one sentence when there is nothing to
//! suggest. With text, a line above the results states what was searched and where, with
//! the scope beside it; with no match, a sentence names the query and offers to widen a
//! narrowed scope. What the page says is `library/search.rs`.

use std::cell::RefCell;
use std::rc::Rc;

use adw::prelude::*;
use storyarc_core::domain::Publication;

use crate::library::search::{Scope, SearchPage};
use crate::strings::tr;

/// The search page's widgets.
pub struct SearchUi {
    /// Above the results: the line and the scope.
    pub strip: gtk::Box,
    line: gtk::Label,
    pub scope: gtk::DropDown,
    /// Suggestions, nothing to suggest, or no results.
    pub page: adw::StatusPage,
    recent: gtk::ListBox,
    /// Publications the reader already has, offered before a word is typed.
    suggested: gtk::ListBox,
    offered: Rc<RefCell<Vec<Publication>>>,
    pub clear: gtk::Button,
    pub widen: gtk::Button,
    add: gtk::Button,
}

/// What a row of the recent searches holds: the query it puts back in the field.
pub const RECENT_ROW: &str = "recent";

impl SearchUi {
    pub fn new() -> Self {
        let line = gtk::Label::builder()
            .xalign(0.0)
            .hexpand(true)
            .ellipsize(gtk::pango::EllipsizeMode::End)
            .css_classes(["dimmed"])
            .build();
        let scopes = [Scope::Everywhere.label(), Scope::OnDevice.label()];
        let scopes: Vec<&str> = scopes.iter().map(String::as_str).collect();
        let scope = gtk::DropDown::from_strings(&scopes);
        scope.set_tooltip_text(Some(&tr("library.scope", "Show")));
        scope.update_property(&[gtk::accessible::Property::Label(&tr(
            "library.scope",
            "Show",
        ))]);
        let strip = gtk::Box::builder()
            .spacing(12)
            .margin_start(12)
            .margin_end(12)
            .margin_top(6)
            .margin_bottom(6)
            .visible(false)
            .build();
        strip.append(&line);
        strip.append(&scope);

        let recent = gtk::ListBox::builder()
            .css_classes(["boxed-list"])
            .selection_mode(gtk::SelectionMode::None)
            .build();
        let clear = gtk::Button::builder()
            .label(tr("library.search.recent.clear", "Clear recent searches"))
            .halign(gtk::Align::Center)
            .css_classes(["flat"])
            .build();
        let widen = gtk::Button::builder()
            .label(tr("library.scope.all", "Everywhere"))
            .halign(gtk::Align::Center)
            .css_classes(["pill"])
            .build();
        let add = gtk::Button::builder()
            .label(tr("library.addSource", "Add Folder…"))
            .action_name("win.add-source")
            .halign(gtk::Align::Center)
            .css_classes(["pill", "suggested-action"])
            .build();
        let suggested = gtk::ListBox::builder()
            .css_classes(["boxed-list"])
            .selection_mode(gtk::SelectionMode::None)
            .build();
        let children = gtk::Box::builder()
            .orientation(gtk::Orientation::Vertical)
            .spacing(12)
            .build();
        children.append(&suggested);
        children.append(&recent);
        children.append(&clear);
        children.append(&widen);
        children.append(&add);
        let page = adw::StatusPage::builder()
            .icon_name("system-search-symbolic")
            .child(
                &adw::Clamp::builder()
                    .maximum_size(480)
                    .child(&children)
                    .build(),
            )
            .build();
        Self {
            strip,
            line,
            scope,
            page,
            recent,
            suggested,
            offered: Rc::default(),
            clear,
            widen,
            add,
        }
    }

    /// Shows what the page says, with `offered` as the publications suggested before a
    /// word is typed. Returns whether the results grid should show.
    pub fn show(&self, page: &SearchPage, searching: bool, offered: Vec<Publication>) -> bool {
        self.strip.set_visible(searching);
        self.clear.set_visible(false);
        self.widen.set_visible(false);
        self.add.set_visible(false);
        self.recent.set_visible(false);
        self.suggested.set_visible(false);
        self.page.set_description(None);
        match page {
            SearchPage::Results { line } => {
                self.line.set_label(line);
                return true;
            }
            SearchPage::Suggestions(recent) => {
                self.line.set_label("");
                self.page.set_title(&tr("library.search", "Search"));
                self.suggested.remove_all();
                for publication in &offered {
                    let row = adw::ActionRow::builder()
                        .title(&publication.display_title)
                        .use_markup(false)
                        .activatable(true)
                        .build();
                    if let Some(author) = publication.authors.first() {
                        row.set_subtitle(author);
                    }
                    row.add_prefix(&gtk::Image::from_icon_name("x-office-document-symbolic"));
                    self.suggested.append(&row);
                }
                self.suggested.set_visible(!offered.is_empty());
                *self.offered.borrow_mut() = offered;
                self.recent.remove_all();
                for query in recent {
                    let row = adw::ActionRow::builder()
                        .title(query)
                        .use_markup(false)
                        .activatable(true)
                        .name(RECENT_ROW)
                        .build();
                    row.add_prefix(&gtk::Image::from_icon_name("document-open-recent-symbolic"));
                    self.recent.append(&row);
                }
                self.recent.set_visible(!recent.is_empty());
                self.clear.set_visible(!recent.is_empty());
                if !recent.is_empty() {
                    self.page
                        .set_description(Some(&tr("library.search.recent", "Recent searches")));
                }
            }
            SearchPage::NothingToSuggest => {
                self.line.set_label("");
                self.page
                    .set_title(&tr("library.empty.title", "Nothing here yet"));
                self.page.set_description(Some(&tr(
                    "library.empty.subtitle",
                    "Choose a file and start reading. You can add a whole folder whenever you like.",
                )));
                self.add.set_visible(true);
            }
            SearchPage::NoResults { line, can_widen } => {
                self.line.set_label("");
                self.page.set_title(line);
                self.widen.set_visible(*can_widen);
            }
        }
        false
    }

    /// Calls `chosen` with a suggested publication the reader picks.
    pub fn on_suggested(&self, chosen: impl Fn(&Publication) + 'static) {
        let offered = self.offered.clone();
        self.suggested.connect_row_activated(move |_, row| {
            let publication = offered
                .borrow()
                .get(usize::try_from(row.index()).unwrap_or(usize::MAX))
                .cloned();
            if let Some(publication) = publication {
                chosen(&publication);
            }
        });
    }

    /// Calls `chosen` with the query of a recent search the reader picks.
    pub fn on_recent(&self, chosen: impl Fn(String) + 'static) {
        self.recent.connect_row_activated(move |_, row| {
            if let Some(row) = row.downcast_ref::<adw::ActionRow>() {
                chosen(row.title().to_string());
            }
        });
    }
}

/// The scope a drop-down position stands for, and back.
pub fn scope_at(position: u32) -> Scope {
    if position == 1 {
        Scope::OnDevice
    } else {
        Scope::Everywhere
    }
}

pub fn position_of(scope: Scope) -> u32 {
    match scope {
        Scope::Everywhere => 0,
        Scope::OnDevice => 1,
    }
}
