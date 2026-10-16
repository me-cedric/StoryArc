//! The library window: the wave 1 shell (sidebar, content, narrow breakpoint) with the
//! command table's primary menu and the toast overlay the app names a failure in. The
//! grid, list, search, Home and detail are tasks 2.35a to 2.35d and wait for the
//! core's library API; the content page is still the empty state.

use adw::prelude::*;
use gtk::glib;

use crate::app::Shared;
use crate::commands::Scope;
use crate::menus;
use crate::session;
use crate::strings::{tr, tr_args};
use crate::window_state::{MIN_HEIGHT, MIN_WIDTH, WindowState};

const SECTIONS: [(&str, &str); 3] = [
    ("sidebar.home", "Home"),
    ("sidebar.library", "Library"),
    ("sidebar.downloads", "Downloads"),
];

/// Builds and presents the library window. `missing` names the readers that could not
/// be reopened at launch, shown in grey where the library would show its shelves.
pub fn open(shared: &Shared, state: &WindowState, missing: &[String]) -> adw::ApplicationWindow {
    let split = adw::NavigationSplitView::builder()
        .sidebar(&sidebar_page())
        .content(&content_page(missing))
        .build();
    let overlay = adw::ToastOverlay::new();
    overlay.set_child(Some(&split));
    let window = adw::ApplicationWindow::builder()
        .application(&shared.application())
        .title("StoryArc")
        .content(&overlay)
        .build();
    // The minimum size is a size request: libadwaita sets one of its own only from 1.6.
    window.set_size_request(MIN_WIDTH, MIN_HEIGHT);
    session::apply(&window, state);
    menus::add_disabled_actions(&window, Scope::Library, &[]);
    window.add_breakpoint(narrow_breakpoint(&split));

    let weak = std::rc::Rc::downgrade(shared);
    window.connect_close_request(move |_| {
        if let Some(shared) = weak.upgrade()
            && !shared.quitting.get()
        {
            shared.save_session();
        }
        glib::Propagation::Proceed
    });
    *shared.library_toasts.borrow_mut() = Some(overlay);
    *shared.library.borrow_mut() = Some(window.clone());
    window.present();
    window
}

fn narrow_breakpoint(split: &adw::NavigationSplitView) -> adw::Breakpoint {
    let condition = adw::BreakpointCondition::parse("max-width: 600sp").expect("valid condition");
    let breakpoint = adw::Breakpoint::new(condition);
    breakpoint.add_setter(split, "collapsed", Some(&true.to_value()));
    breakpoint
}

fn sidebar_page() -> adw::NavigationPage {
    let list = gtk::ListBox::builder()
        .css_classes(["navigation-sidebar"])
        .build();
    for (key, english) in SECTIONS {
        list.append(
            &gtk::Label::builder()
                .label(tr(key, english))
                .xalign(0.0)
                .build(),
        );
    }
    list.select_row(list.row_at_index(0).as_ref());
    let menu_button = gtk::MenuButton::builder()
        .icon_name("open-menu-symbolic")
        .tooltip_text(tr("menu.main", "Main menu"))
        .menu_model(&menus::primary_menu())
        .primary(true)
        .build();
    let header = adw::HeaderBar::new();
    header.pack_end(&menu_button);
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);
    toolbar.set_content(Some(&list));
    adw::NavigationPage::new(&toolbar, "StoryArc")
}

fn content_page(missing: &[String]) -> adw::NavigationPage {
    let description = if missing.is_empty() {
        tr("library.empty.body", "Your library will appear here.")
    } else {
        tr_args(
            "restore.missing",
            "Could not reopen: %s",
            &[&missing.join(", ")],
        )
    };
    let status = adw::StatusPage::builder()
        .icon_name(crate::APP_ID)
        .title(tr("library.empty.title", "Nothing here yet"))
        .description(description)
        .build();
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&adw::HeaderBar::new());
    toolbar.set_content(Some(&status));
    adw::NavigationPage::new(&toolbar, "Home")
}
