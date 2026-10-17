//! Where the publication detail page stands (task 2.35d, `publication-detail`, The page
//! on a large screen): beside the library from 1024 pixels, in an `AdwOverlaySplitView`
//! pane that says in one sentence that nothing is chosen yet; pushed over the library as
//! an `AdwNavigationPage` below that. Narrowing the window moves the page the reader was
//! looking at into the pushed page, and widening it moves it back beside the library.

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::Duration;

use adw::prelude::*;
use gtk::glib;
use storyarc_core::domain::Publication;

use crate::app::Shared;
use crate::library::detail::Placement;
use crate::library_views;
use crate::library_window::{self, LibraryUi};

/// How often the window's width is looked at: a resize settles inside this.
const LOOK: Duration = Duration::from_millis(250);
const DETAIL_TAG: &str = "detail";

pub struct DetailPanes {
    split: adw::OverlaySplitView,
    pane: adw::Bin,
    /// The publication the reader chose, while its page is shown either way.
    pub chosen: RefCell<Option<Publication>>,
    placement: Cell<Placement>,
    /// Set while the window itself moves the page between the two places, so the pop
    /// that does it is not read as the reader going back.
    moving: Cell<bool>,
}

impl DetailPanes {
    pub fn new(split: adw::OverlaySplitView, pane: adw::Bin) -> Self {
        Self {
            split,
            pane,
            chosen: RefCell::default(),
            placement: Cell::default(),
            moving: Cell::new(false),
        }
    }
}

/// Puts the chosen publication's page where the window's width says.
pub fn place(shared: &Shared, ui: &LibraryUi) {
    let panes = &ui.panes;
    let chosen = panes.chosen.borrow().clone();
    let detail_shown = ui
        .navigation
        .visible_page()
        .and_then(|page| page.tag())
        .is_some_and(|tag| tag == DETAIL_TAG);
    match panes.placement.get() {
        Placement::Beside => {
            let child = match &chosen {
                Some(publication) => {
                    let detail = library_window::detail_of(shared, publication);
                    library_views::detail_view(
                        &detail,
                        publication,
                        &ui.covers,
                        library_window::read(shared),
                    )
                    .upcast()
                }
                None => library_views::pane_placeholder(),
            };
            panes.pane.set_child(Some(&child));
            panes.split.set_show_sidebar(true);
            if detail_shown {
                panes.moving.set(true);
                ui.navigation.pop_to_tag("content");
                panes.moving.set(false);
            }
        }
        Placement::Pushed => {
            panes.split.set_show_sidebar(false);
            if let Some(publication) = chosen {
                if detail_shown {
                    panes.moving.set(true);
                    ui.navigation.pop_to_tag("content");
                    panes.moving.set(false);
                }
                let detail = library_window::detail_of(shared, &publication);
                ui.navigation.push(&library_views::detail_page(
                    &detail,
                    &publication,
                    &ui.covers,
                    library_window::read(shared),
                ));
            }
        }
    }
}

/// Follows the window's width, and forgets the chosen publication when the reader goes
/// back from its pushed page.
pub fn follow_width(shared: &Shared, ui: &Rc<LibraryUi>) {
    let weak = Rc::downgrade(ui);
    ui.navigation.connect_popped(move |_, page| {
        let Some(ui) = weak.upgrade() else {
            return;
        };
        if !ui.panes.moving.get() && page.tag().is_some_and(|tag| tag == DETAIL_TAG) {
            ui.panes.chosen.borrow_mut().take();
        }
    });
    let weak_ui = Rc::downgrade(ui);
    let weak_shared = Rc::downgrade(shared);
    glib::timeout_add_local(LOOK, move || {
        let (Some(ui), Some(shared)) = (weak_ui.upgrade(), weak_shared.upgrade()) else {
            return glib::ControlFlow::Break;
        };
        let width = ui.window.width();
        if width > 0 {
            let now = Placement::for_width(width);
            if now != ui.panes.placement.get() {
                ui.panes.placement.set(now);
                place(&shared, &ui);
            }
        }
        glib::ControlFlow::Continue
    });
}
