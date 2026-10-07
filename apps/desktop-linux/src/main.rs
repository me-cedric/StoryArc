//! StoryArc for Linux. Base shell only: no feature code yet.

use adw::prelude::*;
use gtk::{gio, glib};

const APP_ID: &str = "com.mecedric.StoryArc";
const SECTIONS: [&str; 3] = ["Home", "Library", "Downloads"];

fn main() -> glib::ExitCode {
    let app = adw::Application::builder().application_id(APP_ID).build();
    app.connect_startup(install_actions);
    app.connect_startup(|_| find_icon_when_uninstalled());
    app.connect_activate(present_window);
    app.run()
}

// ponytail: a debug build run from the tree has no installed icon, so it reads the source copy.
// An installed or Flatpak build finds the icon in hicolor and skips this.
fn find_icon_when_uninstalled() {
    if let (true, Some(display)) = (cfg!(debug_assertions), gtk::gdk::Display::default()) {
        gtk::IconTheme::for_display(&display)
            .add_search_path(concat!(env!("CARGO_MANIFEST_DIR"), "/data/icons"));
    }
}

fn install_actions(app: &adw::Application) {
    let quit = gio::ActionEntry::builder("quit")
        .activate(|app: &adw::Application, _, _| app.quit())
        .build();
    let about = gio::ActionEntry::builder("about")
        .activate(|app: &adw::Application, _, _| show_about(app))
        .build();
    app.add_action_entries([quit, about]);
    app.set_accels_for_action("app.quit", &["<Control>q"]);
}

fn show_about(app: &adw::Application) {
    let dialog = adw::AboutDialog::builder()
        .application_name("StoryArc")
        .application_icon(APP_ID)
        .developer_name("Cédric Meyer")
        .version(storyarc_core::version())
        .license_type(gtk::License::MitX11)
        .build();
    dialog.present(app.active_window().as_ref());
}

fn present_window(app: &adw::Application) {
    if let Some(window) = app.active_window() {
        window.present();
        return;
    }
    let split = adw::NavigationSplitView::builder()
        .sidebar(&sidebar_page())
        .content(&content_page())
        .build();
    let window = adw::ApplicationWindow::builder()
        .application(app)
        .title("StoryArc")
        .default_width(1100)
        .default_height(720)
        .width_request(360)
        .height_request(294)
        .content(&split)
        .build();
    window.add_breakpoint(narrow_breakpoint(&split));
    window.present();
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
    for name in SECTIONS {
        list.append(&gtk::Label::builder().label(name).xalign(0.0).build());
    }
    list.select_row(list.row_at_index(0).as_ref());
    let menu = gio::Menu::new();
    menu.append(Some("About StoryArc"), Some("app.about"));
    let menu_button = gtk::MenuButton::builder()
        .icon_name("open-menu-symbolic")
        .tooltip_text("Main menu")
        .menu_model(&menu)
        .primary(true)
        .build();
    let header = adw::HeaderBar::new();
    header.pack_end(&menu_button);
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);
    toolbar.set_content(Some(&list));
    adw::NavigationPage::new(&toolbar, "StoryArc")
}

fn content_page() -> adw::NavigationPage {
    let status = adw::StatusPage::builder()
        .icon_name(APP_ID)
        .title("Nothing here yet")
        .description("Your library will appear here.")
        .build();
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&adw::HeaderBar::new());
    toolbar.set_content(Some(&status));
    adw::NavigationPage::new(&toolbar, "Home")
}
